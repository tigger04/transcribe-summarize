// ABOUTME: Configuration loading with priority: CLI > YAML > env > defaults.
// ABOUTME: Validates input file exists and has supported format.

import Foundation
import Yams

/// Shared access to YAML config for token resolution.
/// For secrets (API keys), environment variables take precedence over config file.
/// For other settings, config file takes precedence over environment variables.
enum ConfigStore {
    private static var yamlConfig: [String: Any]?
    private static var isLoaded = false

    static func load() {
        guard !isLoaded else { return }
        yamlConfig = loadYAMLConfig()
        isLoaded = true
    }

    /// Resolve a value from config file first, then environment variable.
    /// Use for non-sensitive settings.
    static func resolve(configKey: String, envKey: String) -> String? {
        load()
        if let value = yamlConfig?[configKey] as? String, !value.isEmpty {
            return value
        }
        return ProcessInfo.processInfo.environment[envKey]
    }

    /// Resolve a secret from environment variable first, then config file.
    /// Environment variables are preferred for secrets to avoid storing them in files.
    static func resolveSecret(configKey: String, envKey: String) -> String? {
        load()
        if let value = ProcessInfo.processInfo.environment[envKey], !value.isEmpty {
            return value
        }
        return yamlConfig?[configKey] as? String
    }

    /// Resolve with multiple possible environment variable names.
    static func resolve(configKey: String, envKeys: [String]) -> String? {
        load()
        if let value = yamlConfig?[configKey] as? String, !value.isEmpty {
            return value
        }
        for key in envKeys {
            if let value = ProcessInfo.processInfo.environment[key] {
                return value
            }
        }
        return nil
    }

    /// Resolve an array value from config file.
    static func resolveArray(configKey: String) -> [String]? {
        load()
        return yamlConfig?[configKey] as? [String]
    }

    private static func loadYAMLConfig() -> [String: Any]? {
        let fm = FileManager.default

        let localPath = ".transcribe.yaml"
        let xdgConfigPath = NSHomeDirectory() + "/.config/transcribe-summarize/config.yaml"
        let legacyHomePath = NSHomeDirectory() + "/.transcribe.yaml"

        var configPath: String?
        if fm.fileExists(atPath: localPath) {
            configPath = localPath
        } else if fm.fileExists(atPath: xdgConfigPath) {
            configPath = xdgConfigPath
        } else if fm.fileExists(atPath: legacyHomePath) {
            configPath = legacyHomePath
        }

        guard let path = configPath,
              let contents = fm.contents(atPath: path),
              let yaml = String(data: contents, encoding: .utf8) else {
            return nil
        }

        return try? Yams.load(yaml: yaml) as? [String: Any]
    }
}

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

        // Resolve LLM: CLI > YAML > env > default (auto)
        let resolvedLLM = llm != "auto" ? llm
            : (yamlConfig?["llm"] as? String)
            ?? ProcessInfo.processInfo.environment["TRANSCRIBE_LLM"]
            ?? "auto"

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

        let validLLMs = ["claude", "openai", "ollama", "auto"]
        guard validLLMs.contains(llm) else {
            fputs("Error: Invalid LLM provider: \(llm)\n", stderr)
            fputs("Valid providers: \(validLLMs.joined(separator: ", "))\n", stderr)
            return false
        }

        return true
    }

    private static func loadYAMLConfig() -> [String: Any]? {
        let fm = FileManager.default

        // Priority: local > ~/.config/transcribe-summarize/config.yaml > legacy ~/.transcribe.yaml
        let localPath = ".transcribe.yaml"
        let xdgConfigPath = NSHomeDirectory() + "/.config/transcribe-summarize/config.yaml"
        let legacyHomePath = NSHomeDirectory() + "/.transcribe.yaml"

        var configPath: String?
        if fm.fileExists(atPath: localPath) {
            configPath = localPath
        } else if fm.fileExists(atPath: xdgConfigPath) {
            configPath = xdgConfigPath
        } else if fm.fileExists(atPath: legacyHomePath) {
            configPath = legacyHomePath
        }

        guard let path = configPath,
              let contents = fm.contents(atPath: path),
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

/// Selects an LLM provider based on availability and priority order.
/// Default priority: ollama > claude > openai (local-first, free before paid).
/// Can be customized via `llm_priority` in config file.
struct LLMSelector {
    static let defaultPriority = ["ollama", "claude", "openai"]
    let priority: [String]

    init(priority: [String]? = nil) {
        // Priority: explicit parameter > config file > default
        if let explicit = priority {
            self.priority = explicit
        } else if let configured = ConfigStore.resolveArray(configKey: "llm_priority") {
            self.priority = configured
        } else {
            self.priority = Self.defaultPriority
        }
    }

    /// Returns the first available provider based on priority order, or nil if none available.
    func selectProvider() -> String? {
        for provider in priority {
            if isAvailable(provider) {
                return provider
            }
        }
        return nil
    }

    /// Checks if a provider has required credentials configured.
    /// Uses resolveSecret for API keys (env vars take precedence for security).
    func isAvailable(_ provider: String) -> Bool {
        switch provider {
        case "ollama":
            // ollama_model is not a secret, use normal resolve
            return ConfigStore.resolve(configKey: "ollama_model", envKey: "OLLAMA_MODEL") != nil
        case "claude":
            return ConfigStore.resolveSecret(configKey: "anthropic_api_key", envKey: "ANTHROPIC_API_KEY") != nil
        case "openai":
            return ConfigStore.resolveSecret(configKey: "openai_api_key", envKey: "OPENAI_API_KEY") != nil
        default:
            return false
        }
    }
}
