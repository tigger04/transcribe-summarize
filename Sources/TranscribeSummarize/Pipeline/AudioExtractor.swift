// ABOUTME: Wrapper for ffmpeg/ffprobe to extract and validate audio.
// ABOUTME: Converts any media file to 16kHz mono WAV for whisper.cpp.

import Foundation

struct AudioExtractor {
    enum AudioError: Error, LocalizedError {
        case ffmpegNotFound
        case ffprobeNotFound
        case extractionFailed(String)
        case invalidDuration
        case tooShort(duration: Double, minimum: Double)
        case corrupted(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg not found. Install with: brew install ffmpeg"
            case .ffprobeNotFound:
                return "ffprobe not found. Install with: brew install ffmpeg"
            case .extractionFailed(let msg):
                return "Audio extraction failed: \(msg)"
            case .invalidDuration:
                return "Could not determine audio duration"
            case .tooShort(let duration, let minimum):
                return String(format: "Audio too short: %.1fs (minimum: %.1fs)", duration, minimum)
            case .corrupted(let msg):
                return "File appears corrupted: \(msg)"
            }
        }
    }

    struct AudioInfo {
        let duration: Double
        let sampleRate: Int
        let channels: Int
        let codec: String
    }

    private let verbose: Int

    init(verbose: Int = 0) {
        self.verbose = verbose
    }

    /// Probe audio file for metadata without extracting.
    func probe(_ inputPath: String) async throws -> AudioInfo {
        guard commandExists("ffprobe") else { throw AudioError.ffprobeNotFound }
        return try await probeAudio(inputPath)
    }

    /// Extract audio from input file to temporary WAV suitable for Whisper.
    /// Returns path to temporary WAV file.
    func extract(from inputPath: String, minimumDuration: Double = 10.0) async throws -> (wavPath: String, info: AudioInfo) {
        guard commandExists("ffmpeg") else { throw AudioError.ffmpegNotFound }
        guard commandExists("ffprobe") else { throw AudioError.ffprobeNotFound }

        let info = try await probeAudio(inputPath)

        guard info.duration >= minimumDuration else {
            throw AudioError.tooShort(duration: info.duration, minimum: minimumDuration)
        }

        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent(UUID().uuidString + ".wav").path

        try await convertToWav(input: inputPath, output: outputPath)

        return (outputPath, info)
    }

    private func probeAudio(_ path: String) async throws -> AudioInfo {
        let args = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            "-select_streams", "a:0",
            path
        ]

        let (output, exitCode) = try await runCommand("ffprobe", arguments: args)

        guard exitCode == 0 else {
            throw AudioError.corrupted("ffprobe failed to read file")
        }

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let durationStr = format["duration"] as? String,
              let duration = Double(durationStr) else {
            throw AudioError.invalidDuration
        }

        var sampleRate = 44100
        var channels = 2
        var codec = "unknown"

        if let streams = json["streams"] as? [[String: Any]], let stream = streams.first {
            sampleRate = (stream["sample_rate"] as? String).flatMap { Int($0) } ?? sampleRate
            channels = stream["channels"] as? Int ?? channels
            codec = stream["codec_name"] as? String ?? codec
        }

        if verbose > 0 {
            print("Audio: \(codec), \(sampleRate)Hz, \(channels)ch, \(String(format: "%.1f", duration))s")
        }

        return AudioInfo(duration: duration, sampleRate: sampleRate, channels: channels, codec: codec)
    }

    private func convertToWav(input: String, output: String) async throws {
        let args = [
            "-i", input,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            "-y",
            output
        ]

        let (stderr, exitCode) = try await runCommand("ffmpeg", arguments: args, captureStderr: true)

        guard exitCode == 0 else {
            throw AudioError.extractionFailed(stderr)
        }

        if verbose > 1 {
            print("Converted to: \(output)")
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

    private func runCommand(_ command: String, arguments: [String], captureStderr: Bool = false) async throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        // Prevent subprocess from reading terminal input
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        if captureStderr {
            process.standardError = pipe
            process.standardOutput = FileHandle.nullDevice
        } else {
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
        }

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (output, process.terminationStatus)
    }

    /// Clean up temporary files
    static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
