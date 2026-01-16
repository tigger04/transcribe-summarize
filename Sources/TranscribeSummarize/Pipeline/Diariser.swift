// ABOUTME: Wrapper for pyannote-audio diarization via Python subprocess.
// ABOUTME: Merges speaker labels with transcript segments.

import Foundation

struct Diariser {
    enum DiariseError: Error, LocalizedError {
        case pythonNotFound
        case venvSetupFailed(String)
        case scriptNotFound
        case noToken
        case diarizationFailed(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .pythonNotFound:
                return "Python 3 not found. Install with: brew install python@3.10"
            case .venvSetupFailed(let msg):
                return "Failed to set up diarization environment: \(msg)"
            case .scriptNotFound:
                return "Diarisation script not found"
            case .noToken:
                return "HuggingFace token not configured. Set HF_TOKEN environment variable."
            case .diarizationFailed(let msg):
                return "Diarisation failed: \(msg)"
            case .parseError(let msg):
                return "Failed to parse diarization output: \(msg)"
            }
        }
    }

    struct DiariseSegment: Codable {
        let start: Double
        let end: Double
        let speaker: String
    }

    private let verbose: Int
    private let speakerNames: [String]

    init(verbose: Int = 0, speakerNames: [String] = []) {
        self.verbose = verbose
        self.speakerNames = speakerNames
    }

    /// Apply speaker labels to transcript segments.
    /// Returns segments with speaker field populated.
    func diarise(wavPath: String, segments: [Segment]) async throws -> [Segment] {
        let diariseSegments: [DiariseSegment]

        do {
            diariseSegments = try await runDiarisation(wavPath: wavPath)
        } catch DiariseError.noToken {
            fputs("Warning: No HuggingFace token configured. Proceeding without speaker labels.\n", stderr)
            fputs("To enable diarization, get a token at: https://huggingface.co/settings/tokens\n", stderr)
            return segments
        } catch {
            fputs("Warning: Diarisation failed: \(error.localizedDescription)\n", stderr)
            fputs("Proceeding without speaker labels.\n", stderr)
            return segments
        }

        let speakerMap = buildSpeakerMap(from: diariseSegments)

        return segments.map { segment in
            var updated = segment
            updated.speaker = findSpeaker(
                for: segment,
                in: diariseSegments,
                speakerMap: speakerMap
            )
            return updated
        }
    }

    private func runDiarisation(wavPath: String) async throws -> [DiariseSegment] {
        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? ProcessInfo.processInfo.environment["HUGGINGFACE_TOKEN"]

        guard token != nil else {
            throw DiariseError.noToken
        }

        // Ensure venv exists (creates on first use)
        try ensureVenvExists()

        let pythonExec = pythonPath()
        guard FileManager.default.isExecutableFile(atPath: pythonExec) else {
            throw DiariseError.pythonNotFound
        }

        let scriptPath = findDiariseScript()
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw DiariseError.scriptNotFound
        }

        if verbose > 0 {
            print("Running speaker diarization...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExec)
        process.arguments = [scriptPath, wavPath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        if let errorResponse = try? JSONDecoder().decode([String: String].self, from: outputData),
           let error = errorResponse["error"] {
            throw DiariseError.diarizationFailed(error)
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
            throw DiariseError.diarizationFailed(stderr)
        }

        return try JSONDecoder().decode([DiariseSegment].self, from: outputData)
    }

    private func venvPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/transcribe-summarize/venv")
    }

    private func ensureVenvExists() throws {
        let venv = venvPath()
        let pythonExec = venv.appendingPathComponent("bin/python3").path

        // Already set up
        if FileManager.default.isExecutableFile(atPath: pythonExec) {
            return
        }

        // Check system python3 exists
        guard commandExists("python3") else {
            throw DiariseError.pythonNotFound
        }

        fputs("Setting up diarization environment (one-time)...\n", stderr)

        // Create parent directory
        let parentDir = venv.deletingLastPathComponent().path
        try FileManager.default.createDirectory(
            atPath: parentDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Create venv
        let createVenv = Process()
        createVenv.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        createVenv.arguments = ["python3", "-m", "venv", venv.path]
        createVenv.standardOutput = FileHandle.nullDevice
        createVenv.standardError = FileHandle.standardError
        try createVenv.run()
        createVenv.waitUntilExit()

        guard createVenv.terminationStatus == 0 else {
            throw DiariseError.venvSetupFailed("Failed to create virtual environment")
        }

        // Install dependencies
        fputs("Installing pyannote.audio (this may take a few minutes)...\n", stderr)

        let pipPath = venv.appendingPathComponent("bin/pip").path
        let installDeps = Process()
        installDeps.executableURL = URL(fileURLWithPath: pipPath)
        installDeps.arguments = ["install", "--quiet", "pyannote.audio", "torch"]
        installDeps.standardOutput = FileHandle.nullDevice
        installDeps.standardError = FileHandle.standardError
        try installDeps.run()
        installDeps.waitUntilExit()

        guard installDeps.terminationStatus == 0 else {
            // Clean up failed venv
            try? FileManager.default.removeItem(at: venv)
            throw DiariseError.venvSetupFailed("Failed to install Python dependencies")
        }

        fputs("Diarisation environment ready.\n", stderr)
    }

    private func pythonPath() -> String {
        // Use managed venv in user's home directory
        let homeVenv = venvPath().appendingPathComponent("bin/python3").path
        if FileManager.default.isExecutableFile(atPath: homeVenv) {
            return homeVenv
        }

        // Fallback for Homebrew cellar location (legacy)
        let brewVenv = "/opt/homebrew/share/transcribe-summarize/venv/bin/python3"
        if FileManager.default.isExecutableFile(atPath: brewVenv) {
            return brewVenv
        }

        // Intel Mac Homebrew location
        let brewVenvIntel = "/usr/local/share/transcribe-summarize/venv/bin/python3"
        if FileManager.default.isExecutableFile(atPath: brewVenvIntel) {
            return brewVenvIntel
        }

        // Should not reach here after ensureVenvExists()
        return venvPath().appendingPathComponent("bin/python3").path
    }

    private func findDiariseScript() -> String {
        let candidates = [
            Bundle.main.bundlePath + "/scripts/diarize.py",
            "./scripts/diarize.py",
            "/opt/homebrew/share/transcribe-summarize/diarize.py",  // ARM Mac
            "/usr/local/share/transcribe-summarize/diarize.py"      // Intel Mac
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return "./scripts/diarize.py"
    }

    private func buildSpeakerMap(from segments: [DiariseSegment]) -> [String: String] {
        var seen = Set<String>()
        var orderedSpeakers: [String] = []

        for seg in segments {
            if !seen.contains(seg.speaker) {
                seen.insert(seg.speaker)
                orderedSpeakers.append(seg.speaker)
            }
        }

        var map: [String: String] = [:]
        for (index, speaker) in orderedSpeakers.enumerated() {
            if index < speakerNames.count {
                map[speaker] = speakerNames[index]
            } else {
                map[speaker] = "Speaker \(index + 1)"
            }
        }

        return map
    }

    private func findSpeaker(for segment: Segment, in diariseSegments: [DiariseSegment], speakerMap: [String: String]) -> String {
        let midpoint = (segment.start + segment.end) / 2

        for dSeg in diariseSegments {
            if midpoint >= dSeg.start && midpoint <= dSeg.end {
                return speakerMap[dSeg.speaker] ?? dSeg.speaker
            }
        }

        let nearest = diariseSegments.min(by: { seg1, seg2 in
            let dist1 = abs(midpoint - (seg1.start + seg1.end) / 2)
            let dist2 = abs(midpoint - (seg2.start + seg2.end) / 2)
            return dist1 < dist2
        })

        if let nearest = nearest {
            return speakerMap[nearest.speaker] ?? nearest.speaker
        }

        return "Unknown"
    }

    private func commandExists(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
