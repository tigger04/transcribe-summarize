// ABOUTME: Wrapper for whisper.cpp to transcribe audio files.
// ABOUTME: Handles model downloading, transcription, JSON parsing, and native output formats.

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

    /// Output formats supported by whisper-cli native output.
    enum OutputFormat {
        case srt       // --output-srt
        case vtt       // --output-vtt
        case jsonFull  // --output-json-full (word-level timestamps with --dtw)

        var whisperFlag: String {
            switch self {
            case .srt: return "-osrt"
            case .vtt: return "-ovtt"
            case .jsonFull: return "-ojf"
            }
        }

        var fileExtension: String {
            switch self {
            case .srt: return ".srt"
            case .vtt: return ".vtt"
            case .jsonFull: return ".json"
            }
        }
    }

    /// Build the base whisper-cli argument array for a transcription run.
    /// Exposed for testability — the subcommand tests verify flag construction.
    func buildWhisperArgs(
        modelPath: String,
        wavPath: String,
        maxLen: Int = 0,
        splitOnWord: Bool = false
    ) -> [String] {
        var args = [
            "-m", modelPath,
            "-f", wavPath,
            "-oj",
            "-of", "",  // placeholder, overwritten by callers
            "-pp"
        ]

        if maxLen > 0 {
            args += ["-ml", "\(maxLen)"]
            if splitOnWord {
                args.append("-sow")
            }
        }

        return args
    }

    func transcribe(wavPath: String, maxLen: Int = 0, splitOnWord: Bool = false) async throws -> [Segment] {
        guard let whisperBinary = findWhisperBinary() else {
            throw TranscribeError.whisperNotFound
        }

        let modelPath = try await ensureModel()
        let segments = try await runWhisper(
            wavPath: wavPath, modelPath: modelPath, binary: whisperBinary,
            maxLen: maxLen, splitOnWord: splitOnWord
        )

        return segments
    }

    /// Run whisper-cli and let it write the output file directly (SRT, VTT, or JSON).
    /// Returns the path to the generated output file.
    func transcribeDirect(
        wavPath: String,
        format: OutputFormat,
        outputBase: String,
        maxLen: Int = 0,
        splitOnWord: Bool = false
    ) async throws -> String {
        guard let whisperBinary = findWhisperBinary() else {
            throw TranscribeError.whisperNotFound
        }

        let modelPath = try await ensureModel()

        var args = [
            "-m", modelPath,
            "-f", wavPath,
            format.whisperFlag,
            "-of", outputBase,
            "-pp"
        ]

        if maxLen > 0 {
            args += ["-ml", "\(maxLen)"]
            if splitOnWord {
                args.append("-sow")
            }
        }

        // For word-level JSON, enable dynamic time warping for token timestamps
        if format == .jsonFull {
            args += ["--dtw", model.rawValue]
        }

        if verbose > 0 {
            print("Running \(whisperBinary) (\(format.fileExtension) output)...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [whisperBinary] + args
        process.standardInput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = verbose > 1 ? nil : FileHandle.nullDevice

        let stderrBuffer = StderrBuffer()
        let verboseLevel = self.verbose

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrBuffer.append(data)
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.contains("progress =") {
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

        stderrPipe.fileHandleForReading.readabilityHandler = nil
        print()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrBuffer.getData(), encoding: .utf8) ?? "Unknown error"
            throw TranscribeError.transcriptionFailed(stderr)
        }

        let outputPath = outputBase + format.fileExtension
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw TranscribeError.parseError("Expected output file not found: \(outputPath)")
        }

        return outputPath
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

    private func runWhisper(
        wavPath: String, modelPath: String, binary: String,
        maxLen: Int = 0, splitOnWord: Bool = false
    ) async throws -> [Segment] {
        let tempDir = FileManager.default.temporaryDirectory
        let outputBase = tempDir.appendingPathComponent(UUID().uuidString).path

        var args = [
            "-m", modelPath,
            "-f", wavPath,
            "-oj",
            "-of", outputBase,
            "-pp"  // print progress
        ]

        if maxLen > 0 {
            args += ["-ml", "\(maxLen)"]
            if splitOnWord {
                args.append("-sow")
            }
        }

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

}
