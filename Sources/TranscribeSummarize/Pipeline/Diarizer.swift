// ABOUTME: Wrapper for speaker diarization via Python subprocess.
// ABOUTME: Supports pyannote (with HF_TOKEN) and speechbrain (no token needed) backends.
// ABOUTME: Merges speaker labels with transcript segments.

import Foundation

struct Diarizer {
    enum DiarizeError: Error, LocalizedError {
        case pythonNotFound
        case venvSetupFailed(String)
        case scriptNotFound
        case diarizationFailed(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .pythonNotFound:
                return "Python 3 not found. Install with: brew install python@3.10"
            case .venvSetupFailed(let msg):
                return "Failed to set up diarization environment: \(msg)"
            case .scriptNotFound:
                return "Diarization script not found"
            case .diarizationFailed(let msg):
                return "Diarization failed: \(msg)"
            case .parseError(let msg):
                return "Failed to parse diarization output: \(msg)"
            }
        }
    }

    struct DiarizeSegment: Codable {
        let start: Double
        let end: Double
        let speaker: String
    }

    private let verbose: Int
    private let speakerNames: [String]
    private let device: String

    init(verbose: Int = 0, speakerNames: [String] = [], device: String = "auto") {
        self.verbose = verbose
        self.speakerNames = speakerNames
        self.device = device
    }

    /// Apply speaker labels to transcript segments.
    /// Returns segments with speaker field populated.
    /// Uses pyannote backend if HF_TOKEN is set, otherwise falls back to speechbrain.
    func diarize(wavPath: String, segments: [Segment]) async throws -> [Segment] {
        let diarizeSegments: [DiarizeSegment]

        do {
            diarizeSegments = try await runDiarization(wavPath: wavPath)
        } catch {
            fputs("Warning: Diarization failed: \(error.localizedDescription)\n", stderr)
            fputs("Proceeding without speaker labels.\n", stderr)
            return segments
        }

        let speakerMap = buildSpeakerMap(from: diarizeSegments)

        return segments.map { segment in
            var updated = segment
            updated.speaker = findSpeaker(
                for: segment,
                in: diarizeSegments,
                speakerMap: speakerMap
            )
            return updated
        }
    }

    private func runDiarization(wavPath: String) async throws -> [DiarizeSegment] {
        // Ensure venv exists (creates on first use)
        try ensureVenvExists()

        let pythonExec = pythonPath()
        guard FileManager.default.isExecutableFile(atPath: pythonExec) else {
            throw DiarizeError.pythonNotFound
        }

        let scriptPath = findDiariseScript()
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw DiarizeError.scriptNotFound
        }

        let token = ConfigStore.resolve(configKey: "hf_token", envKeys: ["HF_TOKEN", "HUGGINGFACE_TOKEN"])
        let backend = token != nil ? "pyannote" : "speechbrain"

        print("  Using \(backend) backend on \(device)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExec)
        process.arguments = [scriptPath, wavPath, "--device", device]

        // Set environment for PyTorch 2.6+ compatibility
        var env = ProcessInfo.processInfo.environment
        env["TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD"] = "1"
        process.environment = env

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // Stream stderr directly to terminal for progress output
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        if let errorResponse = try? JSONDecoder().decode([String: String].self, from: outputData),
           let error = errorResponse["error"] {
            throw DiarizeError.diarizationFailed(error)
        }

        guard process.terminationStatus == 0 else {
            throw DiarizeError.diarizationFailed("Process exited with status \(process.terminationStatus)")
        }

        return try JSONDecoder().decode([DiarizeSegment].self, from: outputData)
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
            throw DiarizeError.pythonNotFound
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
            throw DiarizeError.venvSetupFailed("Failed to create virtual environment")
        }

        // Install dependencies for both pyannote and speechbrain backends
        fputs("Installing diarization dependencies (this may take a few minutes)...\n", stderr)

        let pipPath = venv.appendingPathComponent("bin/pip").path
        let installDeps = Process()
        installDeps.executableURL = URL(fileURLWithPath: pipPath)
        // pyannote.audio for HF_TOKEN users, speechbrain for fallback
        // scikit-learn needed for clustering in speechbrain backend
        installDeps.arguments = ["install", "--quiet", "pyannote.audio", "speechbrain", "scikit-learn", "torch", "torchaudio"]
        installDeps.standardOutput = FileHandle.nullDevice
        installDeps.standardError = FileHandle.standardError
        try installDeps.run()
        installDeps.waitUntilExit()

        guard installDeps.terminationStatus == 0 else {
            // Clean up failed venv
            try? FileManager.default.removeItem(at: venv)
            throw DiarizeError.venvSetupFailed("Failed to install Python dependencies")
        }

        fputs("Diarization environment ready.\n", stderr)
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

    private func buildSpeakerMap(from segments: [DiarizeSegment]) -> [String: String] {
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

    private func findSpeaker(for segment: Segment, in diarizeSegments: [DiarizeSegment], speakerMap: [String: String]) -> String {
        let midpoint = (segment.start + segment.end) / 2

        for dSeg in diarizeSegments {
            if midpoint >= dSeg.start && midpoint <= dSeg.end {
                return speakerMap[dSeg.speaker] ?? dSeg.speaker
            }
        }

        let nearest = diarizeSegments.min(by: { seg1, seg2 in
            let dist1 = abs(midpoint - (seg1.start + seg1.end) / 2)
            let dist2 = abs(midpoint - (seg2.start + seg2.end) / 2)
            return dist1 < dist2
        })

        if let nearest = nearest {
            return speakerMap[nearest.speaker] ?? nearest.speaker
        }

        return "Unknown"
    }

}
