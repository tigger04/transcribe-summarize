// ABOUTME: Wrapper for ffmpeg/ffprobe to extract and validate audio.
// ABOUTME: Converts any media file to 16kHz mono WAV for whisper.cpp.
// ABOUTME: Supports automatic audio quality analysis and preprocessing.

import Foundation

/// Controls audio preprocessing behaviour.
enum PreprocessMode: String, CaseIterable {
    case auto     // Analyze and apply beneficial preprocessing automatically
    case none     // Skip preprocessing entirely
    case analyze  // Report metrics without processing (for dry-run/debugging)
}

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

    /// Audio quality metrics from ffmpeg analysis.
    struct AudioMetrics {
        let meanVolume: Double      // Average loudness in dB
        let maxVolume: Double       // Peak level in dB
        let rmsLevel: Double        // RMS level in dB
        let noiseFloor: Double?     // Background noise level in dB (may be unavailable)
        let crestFactor: Double     // Dynamic range (peak/RMS ratio)

        var needsNormalization: Bool { meanVolume < -30.0 }
        var needsCompression: Bool { maxVolume - meanVolume > 20.0 }
        var needsDenoising: Bool { (noiseFloor ?? -100) > -40.0 }
        var needsAmplification: Bool { rmsLevel < -35.0 }

        var suggestedFilters: [String] {
            var filters: [String] = []
            if needsAmplification {
                filters.append("volume=2")
            }
            if needsDenoising {
                filters.append("afftdn=nf=-25")
            }
            if needsNormalization {
                filters.append("loudnorm=I=-16:TP=-1.5:LRA=11")
            }
            if needsCompression {
                filters.append("dynaudnorm")
            }
            return filters
        }

        var description: String {
            var lines = [
                "Audio Quality Metrics:",
                "  Mean volume: \(String(format: "%.1f", meanVolume)) dB",
                "  Max volume: \(String(format: "%.1f", maxVolume)) dB",
                "  RMS level: \(String(format: "%.1f", rmsLevel)) dB",
                "  Crest factor: \(String(format: "%.2f", crestFactor))"
            ]
            if let noise = noiseFloor {
                lines.append("  Noise floor: \(String(format: "%.1f", noise)) dB")
            }
            lines.append("")
            lines.append("Recommendations:")
            if needsAmplification { lines.append("  - Amplify (RMS too low)") }
            if needsDenoising { lines.append("  - Denoise (noise floor too high)") }
            if needsNormalization { lines.append("  - Normalize (mean volume too low)") }
            if needsCompression { lines.append("  - Compress dynamics (wide dynamic range)") }
            if suggestedFilters.isEmpty { lines.append("  - None needed (audio quality is good)") }
            return lines.joined(separator: "\n")
        }
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
    /// - Parameters:
    ///   - inputPath: Path to input audio/video file
    ///   - minimumDuration: Minimum duration in seconds (default: 10.0)
    ///   - preprocess: Preprocessing mode (default: .auto)
    func extract(
        from inputPath: String,
        minimumDuration: Double = 10.0,
        preprocess: PreprocessMode = .auto
    ) async throws -> (wavPath: String, info: AudioInfo, metrics: AudioMetrics?) {
        guard commandExists("ffmpeg") else { throw AudioError.ffmpegNotFound }
        guard commandExists("ffprobe") else { throw AudioError.ffprobeNotFound }

        let info = try await probeAudio(inputPath)

        guard info.duration >= minimumDuration else {
            throw AudioError.tooShort(duration: info.duration, minimum: minimumDuration)
        }

        // Analyze audio quality if preprocessing is enabled
        var metrics: AudioMetrics?
        var filters: [String] = []

        if preprocess != .none {
            metrics = try await analyzeAudio(inputPath)
            if let m = metrics {
                if verbose > 0 {
                    print(m.description)
                }
                if preprocess == .auto {
                    filters = m.suggestedFilters
                    if !filters.isEmpty && verbose > 0 {
                        print("\nApplying filters: \(filters.joined(separator: ", "))")
                    }
                }
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent(UUID().uuidString + ".wav").path

        try await convertToWav(input: inputPath, output: outputPath, filters: filters)

        return (outputPath, info, metrics)
    }

    /// Analyze audio quality metrics without extracting.
    /// Useful for dry-run or debugging poor transcriptions.
    func analyzeAudio(_ inputPath: String) async throws -> AudioMetrics {
        guard commandExists("ffmpeg") else { throw AudioError.ffmpegNotFound }

        // Run volumedetect and astats in a single pass
        let args = [
            "-i", inputPath,
            "-af", "volumedetect,astats=metadata=1:reset=1",
            "-f", "null",
            "-"
        ]

        let (stderr, _) = try await runCommand("ffmpeg", arguments: args, captureStderr: true)

        // Parse volumedetect output using traditional regex
        var meanVolume: Double = -30.0
        var maxVolume: Double = 0.0
        if let value = extractValue(from: stderr, pattern: "mean_volume:\\s*(-?[\\d.]+)\\s*dB") {
            meanVolume = value
        }
        if let value = extractValue(from: stderr, pattern: "max_volume:\\s*(-?[\\d.]+)\\s*dB") {
            maxVolume = value
        }

        // Parse astats output
        var rmsLevel: Double = -30.0
        var noiseFloor: Double?
        var crestFactor: Double = 3.0
        if let value = extractValue(from: stderr, pattern: "RMS level dB:\\s*(-?[\\d.]+)") {
            rmsLevel = value
        }
        if let value = extractValue(from: stderr, pattern: "Noise floor dB:\\s*(-?[\\d.]+)") {
            noiseFloor = value
        }
        if let value = extractValue(from: stderr, pattern: "Crest factor:\\s*([\\d.]+)") {
            crestFactor = value
        }

        return AudioMetrics(
            meanVolume: meanVolume,
            maxVolume: maxVolume,
            rmsLevel: rmsLevel,
            noiseFloor: noiseFloor,
            crestFactor: crestFactor
        )
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

    private func convertToWav(input: String, output: String, filters: [String] = []) async throws {
        var args = ["-i", input]

        // Build audio filter chain: preprocessing filters + resampling
        var filterChain = filters
        filterChain.append("aresample=16000")  // Resample to 16kHz for whisper
        args += ["-af", filterChain.joined(separator: ",")]

        args += [
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

    /// Extract a numeric value from text using a regex pattern with a capture group.
    private func extractValue(from text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    /// Clean up temporary files
    static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
