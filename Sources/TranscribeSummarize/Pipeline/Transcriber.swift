// ABOUTME: Wrapper for whisper.cpp to transcribe audio files.
// ABOUTME: Handles model downloading, transcription, and JSON parsing.

import Foundation

struct Transcriber {
    enum TranscribeError: Error, LocalizedError {
        case whisperNotFound
        case modelNotFound(String)
        case downloadFailed(String)
        case transcriptionFailed(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .whisperNotFound:
                return "whisper-cli not found. Install with: brew install whisper-cpp"
            case .modelNotFound(let model):
                return "Whisper model '\(model)' not found. Will attempt download."
            case .downloadFailed(let msg):
                return "Model download failed: \(msg)"
            case .transcriptionFailed(let msg):
                return "Transcription failed: \(msg)"
            case .parseError(let msg):
                return "Failed to parse whisper output: \(msg)"
            }
        }
    }

    enum Model: String, CaseIterable {
        case tiny, base, small, medium, large

        var filename: String { "ggml-\(rawValue).bin" }

        var downloadURL: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
        }

        var approximateSize: String {
            switch self {
            case .tiny: return "75MB"
            case .base: return "142MB"
            case .small: return "466MB"
            case .medium: return "1.5GB"
            case .large: return "2.9GB"
            }
        }
    }

    private let model: Model
    private let verbose: Int
    private let modelsDir: URL

    init(model: Model, verbose: Int = 0) {
        self.model = model
        self.verbose = verbose
        self.modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/whisper")
    }

    // Find the whisper binary - try whisper-cli first (new), then whisper-cpp (old)
    private func findWhisperBinary() -> String? {
        for binary in ["whisper-cli", "whisper-cpp"] {
            if commandExists(binary) {
                return binary
            }
        }
        return nil
    }

    func transcribe(wavPath: String) async throws -> [Segment] {
        guard let whisperBinary = findWhisperBinary() else {
            throw TranscribeError.whisperNotFound
        }

        let modelPath = try await ensureModel()
        let segments = try await runWhisper(wavPath: wavPath, modelPath: modelPath, binary: whisperBinary)

        return segments
    }

    private func ensureModel() async throws -> String {
        let modelPath = modelsDir.appendingPathComponent(model.filename).path

        if FileManager.default.fileExists(atPath: modelPath) {
            if verbose > 0 {
                print("Using model: \(modelPath)")
            }
            return modelPath
        }

        print("Model '\(model.rawValue)' not found. Downloading (~\(model.approximateSize))...")

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let (data, response) = try await URLSession.shared.data(from: model.downloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranscribeError.downloadFailed("HTTP error")
        }

        try data.write(to: URL(fileURLWithPath: modelPath))
        print("Model downloaded: \(modelPath)")

        return modelPath
    }

    // Thread-safe buffer for capturing stderr while streaming progress
    private final class StderrBuffer: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()

        func append(_ newData: Data) {
            lock.lock()
            defer { lock.unlock() }
            data.append(newData)
        }

        func getData() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private func runWhisper(wavPath: String, modelPath: String, binary: String) async throws -> [Segment] {
        let tempDir = FileManager.default.temporaryDirectory
        let outputBase = tempDir.appendingPathComponent(UUID().uuidString).path

        let args = [
            "-m", modelPath,
            "-f", wavPath,
            "-oj",
            "-of", outputBase,
            "-pp"  // print progress
        ]

        if verbose > 0 {
            print("Running \(binary)...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binary] + args

        // Prevent subprocess from reading terminal input
        process.standardInput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = verbose > 1 ? nil : FileHandle.nullDevice

        // Thread-safe buffer for capturing stderr
        let stderrBuffer = StderrBuffer()
        let verboseLevel = self.verbose

        // Stream stderr in real-time to show progress
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrBuffer.append(data)
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.contains("progress =") {
                            // Overwrite line with \r for clean progress display
                            print("\r  \(trimmed)", terminator: "")
                            fflush(stdout)
                        } else if verboseLevel > 1 && !trimmed.isEmpty {
                            print(trimmed)
                        }
                    }
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        // Clean up handler and print newline after progress
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        print() // newline after progress line

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrBuffer.getData(), encoding: .utf8) ?? "Unknown error"
            throw TranscribeError.transcriptionFailed(stderr)
        }

        let jsonPath = outputBase + ".json"
        defer { try? FileManager.default.removeItem(atPath: jsonPath) }

        return try parseWhisperJSON(jsonPath)
    }

    private func parseWhisperJSON(_ path: String) throws -> [Segment] {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw TranscribeError.parseError("Could not read output file")
        }

        // whisper-cli JSON format (as of v1.8+)
        struct WhisperOutput: Codable {
            struct WhisperSegment: Codable {
                struct Offsets: Codable {
                    let from: Int  // milliseconds
                    let to: Int    // milliseconds
                }
                let offsets: Offsets
                let text: String
            }
            let transcription: [WhisperSegment]
        }

        let output = try JSONDecoder().decode(WhisperOutput.self, from: data)

        return output.transcription.map { seg in
            Segment(
                start: Double(seg.offsets.from) / 1000.0,
                end: Double(seg.offsets.to) / 1000.0,
                text: seg.text.trimmingCharacters(in: .whitespaces),
                speaker: nil,
                confidence: 1.0  // whisper-cli no longer provides per-segment confidence
            )
        }
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
