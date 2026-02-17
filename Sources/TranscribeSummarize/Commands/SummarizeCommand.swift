// ABOUTME: Subcommand for the full summarize pipeline.
// ABOUTME: Transcribes, diarizes, summarizes via LLM, and outputs structured markdown.

import ArgumentParser
import Foundation

struct SummarizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "summarize",
        abstract: "Transcribe and generate an LLM-powered meeting summary.",
        discussion: """
            Runs the full pipeline: extract audio, transcribe with whisper.cpp,
            identify speakers, generate summary via LLM, and write markdown output.

            LLM auto-selection (--llm auto):
              Default priority: ollama > claude > openai
              Customize with llm_priority in config file.
            """
    )

    @OptionGroup var common: CommonOptions

    @Flag(name: [.short, .long], inversion: .prefixedNo, help: "Include timestamps (default: true)")
    var timestamps: Bool = true

    @Option(name: [.short, .long], help: "Minimum confidence threshold (0.0-1.0, default: 0.8)")
    var confidence: Double = 0.8

    @Option(name: .long, help: "LLM provider: claude, openai, ollama, auto (default: auto)")
    var llm: String = "auto"

    @Flag(name: .long, help: "Show what would be done without processing")
    var dryRun: Bool = false

    mutating func run() async throws {
        let config = try Config.load(
            inputFile: common.inputFile,
            output: common.output,
            speakers: common.speakers,
            timestamps: timestamps,
            confidence: confidence,
            model: common.model ?? "",
            llm: llm,
            preprocess: common.preprocess,
            device: common.device,
            verbose: common.verbose,
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
        print("  Preprocess: \(config.preprocess.rawValue)")
        print("  Diarization device: \(config.device.rawValue)")
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

        if config.preprocess != .none {
            if let metrics = try? await extractor.analyzeAudio(config.inputFile) {
                print(metrics.description)
                print()
            }
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

        // Step 1: Extract audio (with optional preprocessing)
        if config.preprocess == .auto {
            print("Extracting and preprocessing audio...")
        } else {
            print("Extracting audio...")
        }
        let extractor = AudioExtractor(verbose: config.verbose)
        let (wavPath, audioInfo, _) = try await extractor.extract(
            from: config.inputFile,
            preprocess: config.preprocess
        )
        tempFiles.append(wavPath)

        if config.verbose > 0 {
            print("Duration: \(MarkdownWriter.formatDuration(audioInfo.duration))")
        }

        // Step 2: Transcribe
        print("Transcribing...")
        let whisperModel = Transcriber.Model(rawValue: config.model.rawValue) ?? .small
        let transcriber = Transcriber(model: whisperModel, verbose: config.verbose)
        var segments = try await transcriber.transcribe(wavPath: wavPath)

        if config.verbose > 0 {
            print("Transcribed \(segments.count) segments")
        }

        // Step 3: Diarise (optional)
        print("Identifying speakers...")
        let diarizer = Diarizer(verbose: config.verbose, speakerNames: config.speakers, device: config.device.rawValue)
        segments = try await diarizer.diarize(wavPath: wavPath, segments: segments)

        // Step 4: Summarise
        print("Generating summary...")
        let transcriptText = segments.map { seg in
            let speaker = seg.speaker ?? "Speaker"
            return "[\(seg.startTimestamp)] \(speaker): \(seg.text)"
        }.joined(separator: "\n")

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

        summary.duration = MarkdownWriter.formatDuration(audioInfo.duration)
        summary.participants = Array(Set(segments.compactMap { $0.speaker })).sorted()
        summary.confidenceRating = MarkdownWriter.calculateConfidenceRating(segments: segments)

        if summary.title.isEmpty {
            summary.title = MarkdownWriter.defaultTitle(from: config.inputFile)
        }

        // Step 5: Write output
        print("Writing output...")
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
}
