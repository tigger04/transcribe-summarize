// ABOUTME: Entry point for transcribe-summarize CLI.
// ABOUTME: Implements ArgumentParser command with all CLI flags from vision spec.

import ArgumentParser
import Foundation

@main
struct TranscribeSummarize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe-summarize",
        abstract: "Transcribe audio files and generate meeting summaries.",
        version: "0.1.0"
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

    @Option(name: .long, help: "LLM provider: claude, openai, llama (default: claude)")
    var llm: String = "claude"

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
            print("Dry run: would process \(config.inputFile)")
            print("  Output: \(config.outputPath)")
            print("  Model: \(config.model.rawValue)")
            print("  LLM: \(config.llm)")
            return
        }

        // Pipeline execution will be added in subsequent phases
        print("Processing: \(config.inputFile)")
    }
}
