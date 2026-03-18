// ABOUTME: Configuration loading with priority: CLI > YAML > env > defaults.
// ABOUTME: Validates input file exists and has supported format.

import Foundation
import Yams

/// Result of checking a `_command` config key.
enum ConfigCommandStatus: Equatable {
    case notConfigured
    case resolved
    case failed(key: String, exitCode: Int32)
    case emptyOutput(key: String)
    case launchError(key: String, message: String)
    case timedOut(key: String)
}

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

    /// Resolve a secret from environment variable first, then command, then config file.
    /// Environment variables are preferred for secrets to avoid storing them in files.
    /// Commands (e.g. `anthropic_api_key_command`) are checked between env and plain value.
    static func resolveSecret(configKey: String, envKey: String) -> String? {
        load()
        if let value = ProcessInfo.processInfo.environment[envKey], !value.isEmpty {
            return value
        }
        if let commandValue = runConfigCommand(for: configKey) {
            return commandValue
        }
        return yamlConfig?[configKey] as? String
    }

    /// Resolve a secret with multiple possible environment variable names.
    /// Priority: any env var > command > plain config value.
    static func resolveSecret(configKey: String, envKeys: [String]) -> String? {
        load()
        for key in envKeys {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                return value
            }
        }
        if let commandValue = runConfigCommand(for: configKey) {
            return commandValue
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

    /// Check whether a `<configKey>_command` is configured and working.
    /// Returns a diagnostic status without side effects.
    static func checkConfigCommand(for configKey: String) -> ConfigCommandStatus {
        load()
        let commandKey = "\(configKey)_command"
        guard let command = yamlConfig?[commandKey] as? String, !command.isEmpty else {
            return .notConfigured
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            return .launchError(key: commandKey, message: error.localizedDescription)
        }

        let deadline = DispatchTime.now() + .seconds(10)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return .timedOut(key: commandKey)
        }

        guard process.terminationStatus == 0 else {
            return .failed(key: commandKey, exitCode: process.terminationStatus)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return .failed(key: commandKey, exitCode: -1)
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .emptyOutput(key: commandKey)
        }

        return .resolved
    }

    /// Run a `<configKey>_command` from YAML config and return its stdout.
    /// Returns nil if the command key is absent, the command fails, or output is empty.
    /// Prints a warning to stderr on failure (but not when the key is simply absent).
    private static func runConfigCommand(for configKey: String) -> String? {
        let commandKey = "\(configKey)_command"
        guard let command = yamlConfig?[commandKey] as? String, !command.isEmpty else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            fputs("Warning: failed to run \(commandKey): \(error.localizedDescription)\n", stderr)
            return nil
        }

        // 10-second timeout
        let deadline = DispatchTime.now() + .seconds(10)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            fputs("Warning: \(commandKey) timed out after 10 seconds\n", stderr)
            return nil
        }

        guard process.terminationStatus == 0 else {
            fputs("Warning: \(commandKey) exited with status \(process.terminationStatus)\n", stderr)
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            fputs("Warning: \(commandKey) produced empty output\n", stderr)
            return nil
        }
        return trimmed
    }

    /// Resolve an array value from config file.
    static func resolveArray(configKey: String) -> [String]? {
        load()
        return yamlConfig?[configKey] as? [String]
    }

    /// Reset ConfigStore state. Internal for testing.
    static func _resetForTesting() {
        yamlConfig = nil
        isLoaded = false
    }

    /// Inject test config without loading from disk. Internal for testing.
    static func _setTestConfig(_ config: [String: Any]) {
        yamlConfig = config
        isLoaded = true
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
    let model: Transcriber.ModelSpec
    let llm: String
    let preprocess: PreprocessMode
    let device: DeviceMode
    let verbose: Int
    let dryRun: Bool

    enum WhisperModel: String, CaseIterable {
        case tiny, base, small, medium, large
    }

    /// The model name as a string, for display and comparison.
    var modelName: String { model.name }

    enum DeviceMode: String, CaseIterable {
        case auto, cpu, mps, cuda
    }

    static func load(
        inputFile: String,
        output: String?,
        speakers: String?,
        timestamps: Bool,
        confidence: Double,
        model: String,
        llm: String,
        preprocess: String,
        device: String,
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
        let resolvedModel: Transcriber.ModelSpec
        if !model.isEmpty {
            resolvedModel = Transcriber.ModelSpec.from(model)
        } else if let yamlModel = yamlConfig?["model"] as? String, !yamlModel.isEmpty {
            resolvedModel = Transcriber.ModelSpec.from(yamlModel)
        } else if let envModel = ProcessInfo.processInfo.environment["TRANSCRIBE_MODEL"], !envModel.isEmpty {
            resolvedModel = Transcriber.ModelSpec.from(envModel)
        } else {
            resolvedModel = .known(.small)
        }

        // Resolve LLM: CLI > YAML > env > default (auto)
        let resolvedLLM = llm != "auto" ? llm
            : (yamlConfig?["llm"] as? String)
            ?? ProcessInfo.processInfo.environment["TRANSCRIBE_LLM"]
            ?? "auto"

        // Resolve preprocess: CLI > YAML > default (auto)
        let resolvedPreprocess = PreprocessMode(rawValue: preprocess)
            ?? (yamlConfig?["preprocess"] as? String).flatMap { PreprocessMode(rawValue: $0) }
            ?? .auto

        // Resolve device: CLI > YAML > env > default (auto)
        let resolvedDevice = DeviceMode(rawValue: device)
            ?? (yamlConfig?["device"] as? String).flatMap { DeviceMode(rawValue: $0) }
            ?? ProcessInfo.processInfo.environment["TRANSCRIBE_DEVICE"].flatMap { DeviceMode(rawValue: $0) }
            ?? .auto

        return Config(
            inputFile: inputFile,
            outputPath: resolvedOutput,
            speakers: resolvedSpeakers,
            timestamps: timestamps,
            confidence: confidence,
            model: resolvedModel,
            llm: resolvedLLM,
            preprocess: resolvedPreprocess,
            device: resolvedDevice,
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

    /// Resolve the default whisper model from YAML config or environment.
    /// Used by subcommands that resolve model independently of full Config.load().
    static func resolveDefaultModel() -> Transcriber.ModelSpec {
        let yamlConfig = loadYAMLConfig()
        if let yamlModel = yamlConfig?["model"] as? String, !yamlModel.isEmpty {
            return Transcriber.ModelSpec.from(yamlModel)
        }
        if let envModel = ProcessInfo.processInfo.environment["TRANSCRIBE_MODEL"], !envModel.isEmpty {
            return Transcriber.ModelSpec.from(envModel)
        }
        return .known(.small)
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

    /// Returns a user-facing message describing how to configure LLM providers.
    /// Used when no provider is available, to mention both env vars and _command keys.
    func unavailableMessage() -> String {
        var lines: [String] = []
        lines.append("Error: No LLM provider available. Configure one of:")
        lines.append("  - OLLAMA_MODEL (e.g., llama3.1:8b) for local Ollama")
        lines.append("  - ANTHROPIC_API_KEY for Claude (env var or anthropic_api_key_command in config)")
        lines.append("  - OPENAI_API_KEY for OpenAI (env var or openai_api_key_command in config)")
        return lines.joined(separator: "\n")
    }
}
