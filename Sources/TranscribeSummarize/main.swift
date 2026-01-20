// ABOUTME: Entry point for transcribe-summarize CLI.
// ABOUTME: Orchestrates the full pipeline: extract, transcribe, diarize, summarize, output.

import ArgumentParser
import Foundation

@main
struct TranscribeSummarize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe-summarize",
        abstract: "Transcribe audio files and generate meeting summaries.",
        discussion: """
            Config file: ~/.config/transcribe-summarize/config.yaml

            Example config:
              model: small
              llm: auto
              ollama_model: llama3.1:8b
              anthropic_api_key: sk-ant-...  # Overridden by env var
              openai_api_key: sk-...         # Overridden by env var
              hf_token: hf_...               # Overridden by env var
              llm_priority: [ollama, claude, openai]  # Custom order

            LLM auto-selection (--llm auto):
              Default priority: ollama > claude > openai
              Customize with llm_priority in config file.

            Security: Env vars (ANTHROPIC_API_KEY, OPENAI_API_KEY, HF_TOKEN)
            take precedence over config file for secrets.
            """,
        version: "0.2.7"
    )

    @Argument(help: "Path to the audio/video file to transcribe.")
    var inputFile: String

    @Option(name: [.short, .long], help: "Output path (default: input basename + .md)")
    var output: String?

    @Option(name: [.short, .long], help: "Speaker names (comma-separated or path to file)")
    var speakers: String?

    @Flag(name: [.short, .long], inversion: .prefixedNo, help: "Include timestamps (default: true)")
    var timestamps: Bool = true

    @Option(name: [.short, .long], help: "Minimum confidence threshold (0.0-1.0, default: 0.8)")
    var confidence: Double = 0.8

    @Option(name: [.short, .long], help: "Whisper model size (tiny, base, small, medium, large)")
    var model: String = "base"

    @Option(name: .long, help: "LLM provider: claude, openai, ollama, auto (default: auto)")
    var llm: String = "auto"

    @Flag(name: [.short, .long], help: "Increase logging verbosity")
    var verbose: Int

    @Flag(name: .long, help: "Show what would be done without processing")
    var dryRun: Bool = false

    mutating func run() async throws {
        let config = try Config.load(
            inputFile: inputFile,
            output: output,
            speakers: speakers,
            timestamps: timestamps,
            confidence: confidence,
            model: model,
            llm: llm,
            verbose: verbose,
            dryRun: dryRun
        )

        guard config.validate() else {
            throw ExitCode.validationFailure
        }

        if config.dryRun {
            try await runDryRun(config: config)
            return
        }

        try await runPipeline(config: config)
    }

    private func runDryRun(config: Config) async throws {
        print("Dry run: would process \(config.inputFile)\n")

        print("Configuration:")
        print("  Output: \(config.outputPath)")
        print("  Whisper model: \(config.model.rawValue)")
        if config.llm == "auto" {
            let selector = LLMSelector()
            if let selected = selector.selectProvider() {
                print("  LLM provider: auto -> \(selected)")
            } else {
                print("  LLM provider: auto (no provider available)")
            }
        } else {
            print("  LLM provider: \(config.llm)")
        }
        print("  Confidence threshold: \(Int(config.confidence * 100))%")
        print("  Timestamps: \(config.timestamps)")
        print()

        let extractor = AudioExtractor(verbose: config.verbose)
        if let info = try? await extractor.probe(config.inputFile) {
            print("Audio Info:")
            print("  Duration: \(MarkdownWriter.formatDuration(info.duration))")
            print("  Format: \(info.codec), \(info.sampleRate)Hz, \(info.channels)ch")
            print()
        }

        print("Dependencies:")
        printDependencyStatus("ffmpeg")
        printDependencyStatus("whisper-cpp")
        printDependencyStatus("python3", optional: true, note: "for diarization")
        print()

        print("Environment:")
        printEnvStatus("ANTHROPIC_API_KEY", required: config.llm == "claude")
        printEnvStatus("OPENAI_API_KEY", required: config.llm == "openai")
        printEnvStatus("OLLAMA_MODEL", required: config.llm == "ollama")
        printEnvStatus("HF_TOKEN", optional: true, note: "for diarization")
    }

    private func runPipeline(config: Config) async throws {
        var tempFiles: [String] = []
        defer {
            for file in tempFiles {
                try? FileManager.default.removeItem(atPath: file)
            }
        }

        // Step 1: Extract audio
        if config.verbose > 0 { print("Extracting audio...") }
        let extractor = AudioExtractor(verbose: config.verbose)
        let (wavPath, audioInfo) = try await extractor.extract(from: config.inputFile)
        tempFiles.append(wavPath)

        if config.verbose > 0 {
            print("Duration: \(MarkdownWriter.formatDuration(audioInfo.duration))")
        }

        // Step 2: Transcribe
        if config.verbose > 0 { print("Transcribing...") }
        let whisperModel = Transcriber.Model(rawValue: config.model.rawValue) ?? .base
        let transcriber = Transcriber(model: whisperModel, verbose: config.verbose)
        var segments = try await transcriber.transcribe(wavPath: wavPath)

        if config.verbose > 0 {
            print("Transcribed \(segments.count) segments")
        }

        // Step 3: Diarise (optional)
        if config.verbose > 0 { print("Identifying speakers...") }
        let diarizer = Diarizer(verbose: config.verbose, speakerNames: config.speakers)
        segments = try await diarizer.diarize(wavPath: wavPath, segments: segments)

        // Step 4: Summarise
        if config.verbose > 0 { print("Generating summary...") }
        let transcriptText = segments.map { seg in
            let speaker = seg.speaker ?? "Speaker"
            return "[\(seg.startTimestamp)] \(speaker): \(seg.text)"
        }.joined(separator: "\n")

        // Resolve LLM provider (handle "auto" selection)
        let resolvedLLM: String
        if config.llm == "auto" {
            let selector = LLMSelector()
            guard let selected = selector.selectProvider() else {
                fputs("Error: No LLM provider available. Configure one of:\n", stderr)
                fputs("  - OLLAMA_MODEL (e.g., llama3.1:8b) for local Ollama\n", stderr)
                fputs("  - ANTHROPIC_API_KEY for Claude\n", stderr)
                fputs("  - OPENAI_API_KEY for OpenAI\n", stderr)
                throw ExitCode.failure
            }
            resolvedLLM = selected
            if config.verbose > 0 { print("Auto-selected LLM provider: \(resolvedLLM)") }
        } else {
            resolvedLLM = config.llm
        }

        guard let providerType = LLMProviderType(rawValue: resolvedLLM) else {
            fputs("Error: Invalid LLM provider: \(resolvedLLM)\n", stderr)
            throw ExitCode.failure
        }

        let provider = try providerType.createProvider(verbose: config.verbose)
        var summary = try await provider.summarise(transcript: transcriptText)

        // Fill in metadata
        summary.duration = MarkdownWriter.formatDuration(audioInfo.duration)
        summary.participants = Array(Set(segments.compactMap { $0.speaker })).sorted()
        summary.confidenceRating = MarkdownWriter.calculateConfidenceRating(segments: segments)

        if summary.title.isEmpty {
            summary.title = MarkdownWriter.defaultTitle(from: config.inputFile)
        }

        // Step 5: Write output
        if config.verbose > 0 { print("Writing output...") }
        let writer = MarkdownWriter(
            confidenceThreshold: config.confidence,
            includeTimestamps: config.timestamps,
            includeLowConfidence: true
        )

        try writer.write(summary: summary, segments: segments, to: config.outputPath)

        print("Output written to: \(config.outputPath)")
    }

    private func printDependencyStatus(_ name: String, optional: Bool = false, note: String? = nil) {
        let exists = commandExists(name)
        let status = exists ? "✓" : (optional ? "○" : "✗")
        var line = "  \(status) \(name)"
        if let note = note { line += " (\(note))" }
        if !exists && !optional { line += " — MISSING" }
        print(line)
    }

    private func printEnvStatus(_ name: String, required: Bool = false, optional: Bool = false, note: String? = nil) {
        let exists = ProcessInfo.processInfo.environment[name] != nil
        let status = exists ? "✓" : (optional || !required ? "○" : "✗")
        var line = "  \(status) \(name)"
        if let note = note { line += " (\(note))" }
        if !exists && required { line += " — NOT SET" }
        print(line)
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
