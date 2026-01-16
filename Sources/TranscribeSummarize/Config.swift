// ABOUTME: Configuration loading with priority: CLI > YAML > env > defaults.
// ABOUTME: Validates input file exists and has supported format.

import Foundation
import Yams

struct Config {
    let inputFile: String
    let outputPath: String
    let speakers: [String]
    let timestamps: Bool
    let confidence: Double
    let model: WhisperModel
    let llm: String
    let verbose: Int
    let dryRun: Bool

    enum WhisperModel: String, CaseIterable {
        case tiny, base, small, medium, large
    }

    static func load(
        inputFile: String,
        output: String?,
        speakers: String?,
        timestamps: Bool,
        confidence: Double,
        model: String,
        llm: String,
        verbose: Int,
        dryRun: Bool
    ) throws -> Config {
        // Load YAML config if present (local takes precedence over home)
        let yamlConfig = loadYAMLConfig()

        // Resolve output path: CLI > YAML > default (input basename + .md)
        let resolvedOutput = output
            ?? yamlConfig?["output"] as? String
            ?? defaultOutputPath(for: inputFile)

        // Resolve speakers: CLI > YAML > empty
        let resolvedSpeakers = parseSpeakers(speakers)
            ?? (yamlConfig?["speakers"] as? [String])
            ?? []

        // Resolve model: CLI > YAML > env > default
        let resolvedModel = WhisperModel(rawValue: model)
            ?? (yamlConfig?["model"] as? String).flatMap { WhisperModel(rawValue: $0) }
            ?? ProcessInfo.processInfo.environment["TRANSCRIBE_MODEL"].flatMap { WhisperModel(rawValue: $0) }
            ?? .base

        // Resolve LLM: CLI > YAML > env > default
        let resolvedLLM = llm != "claude" ? llm
            : (yamlConfig?["llm"] as? String)
            ?? ProcessInfo.processInfo.environment["TRANSCRIBE_LLM"]
            ?? "claude"

        return Config(
            inputFile: inputFile,
            outputPath: resolvedOutput,
            speakers: resolvedSpeakers,
            timestamps: timestamps,
            confidence: confidence,
            model: resolvedModel,
            llm: resolvedLLM,
            verbose: verbose,
            dryRun: dryRun
        )
    }

    func validate() -> Bool {
        // Skip file existence check for dry-run with nonexistent file
        // (allows checking config without actual file)
        let fm = FileManager.default
        if !dryRun {
            guard fm.fileExists(atPath: inputFile) else {
                fputs("Error: Input file not found: \(inputFile)\n", stderr)
                return false
            }
        }

        let supportedExtensions = ["m4a", "mp4", "wav", "mp3", "opus", "webm", "aac", "flac", "ogg", "mov"]
        let ext = (inputFile as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            fputs("Error: Unsupported format: .\(ext)\n", stderr)
            fputs("Supported: \(supportedExtensions.joined(separator: ", "))\n", stderr)
            return false
        }

        guard confidence >= 0.0 && confidence <= 1.0 else {
            fputs("Error: Confidence must be between 0.0 and 1.0\n", stderr)
            return false
        }

        let validLLMs = ["claude", "openai", "ollama"]
        guard validLLMs.contains(llm) else {
            fputs("Error: Invalid LLM provider: \(llm)\n", stderr)
            fputs("Valid providers: \(validLLMs.joined(separator: ", "))\n", stderr)
            return false
        }

        return true
    }

    private static func loadYAMLConfig() -> [String: Any]? {
        let fm = FileManager.default
        let localPath = ".transcribe.yaml"
        let homePath = NSHomeDirectory() + "/.transcribe.yaml"

        let configPath = fm.fileExists(atPath: localPath) ? localPath : homePath
        guard fm.fileExists(atPath: configPath),
              let contents = fm.contents(atPath: configPath),
              let yaml = String(data: contents, encoding: .utf8) else {
            return nil
        }

        return try? Yams.load(yaml: yaml) as? [String: Any]
    }

    private static func defaultOutputPath(for input: String) -> String {
        let url = URL(fileURLWithPath: input)
        return url.deletingPathExtension().appendingPathExtension("md").path
    }

    private static func parseSpeakers(_ input: String?) -> [String]? {
        guard let input = input else { return nil }

        // Check if it's a file path
        if FileManager.default.fileExists(atPath: input) {
            guard let contents = FileManager.default.contents(atPath: input),
                  let text = String(data: contents, encoding: .utf8) else {
                return nil
            }
            return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }

        // Otherwise, treat as comma-separated list
        return input.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
