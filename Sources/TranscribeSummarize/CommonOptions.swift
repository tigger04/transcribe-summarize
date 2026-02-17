// ABOUTME: Shared CLI options used by all transcribe subcommands.
// ABOUTME: Provides input file, output path, model, speakers, and processing options.

import ArgumentParser
import Foundation

struct CommonOptions: ParsableArguments {
    @Argument(help: "Path to the audio/video file to transcribe.")
    var inputFile: String

    @Option(name: [.short, .long], help: "Output path (default: input basename + format extension)")
    var output: String?

    @Option(name: [.short, .long], help: "Whisper model size (tiny, base, small, medium, large, default: small)")
    var model: String?

    @Option(name: [.short, .long], help: "Speaker names (comma-separated or path to file)")
    var speakers: String?

    @Option(name: .long, help: "Audio preprocessing: auto, none, analyze (default: auto)")
    var preprocess: String = "auto"

    @Option(name: .long, help: "Compute device for diarization: auto, cpu, mps, cuda (default: auto)")
    var device: String = "auto"

    @Flag(name: [.short, .long], help: "Increase logging verbosity")
    var verbose: Int

    /// Resolve the output path, using default extension if not explicitly set.
    func resolveOutputPath(defaultExtension ext: String) -> String {
        if let explicit = output {
            return explicit
        }
        let url = URL(fileURLWithPath: inputFile)
        return url.deletingPathExtension().appendingPathExtension(ext).path
    }

    /// Parse speaker names from the speakers option.
    func parseSpeakerNames() -> [String] {
        guard let speakersInput = speakers else { return [] }

        if FileManager.default.fileExists(atPath: speakersInput) {
            guard let contents = FileManager.default.contents(atPath: speakersInput),
                  let text = String(data: contents, encoding: .utf8) else {
                return []
            }
            return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }

        return speakersInput.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Resolve the whisper model, respecting CLI > YAML > env > default priority.
    func resolveModel() -> Config.WhisperModel {
        if let m = model, let resolved = Config.WhisperModel(rawValue: m) {
            return resolved
        }
        // Fall through to Config resolution with empty model string
        return Config.WhisperModel(rawValue: model ?? "")
            ?? Config.resolveDefaultModel()
    }

    /// Validate that the input file exists and has a supported format.
    func validateInput() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: inputFile) else {
            fputs("Error: Input file not found: \(inputFile)\n", stderr)
            return false
        }

        let supportedExtensions = ["m4a", "mp4", "wav", "mp3", "opus", "webm", "aac", "flac", "ogg", "mov"]
        let ext = (inputFile as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            fputs("Error: Unsupported format: .\(ext)\n", stderr)
            fputs("Supported: \(supportedExtensions.joined(separator: ", "))\n", stderr)
            return false
        }

        return true
    }
}
