// ABOUTME: Subcommand to generate plain text or markdown transcripts.
// ABOUTME: Produces readable output without requiring an LLM provider.

import ArgumentParser
import Foundation

struct TextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Generate a plain text or markdown transcript."
    )

    @OptionGroup var common: CommonOptions

    @Option(name: .long, help: "Output format: txt, md, docx, odt, pdf, html (default: txt)")
    var format: String?

    @Flag(inversion: .prefixedNo, help: "Include timestamps (default: false)")
    var timestamps: Bool = false

    mutating func run() async throws {
        guard common.validateInput() else {
            throw ExitCode.validationFailure
        }

        // Resolve format: explicit flag > output extension > default (txt)
        let resolvedFormat = resolveFormat()
        let outputExt = resolvedFormat.rawValue
        let outputPath = common.resolveOutputPath(defaultExtension: outputExt)

        let whisperModel = common.resolveModel()
        let hasSpeakers = common.speakers != nil

        var tempFiles: [String] = []
        defer {
            for file in tempFiles {
                try? FileManager.default.removeItem(atPath: file)
            }
        }

        // Step 1: Extract audio
        print("Extracting audio...")
        let preprocessMode = PreprocessMode(rawValue: common.preprocess) ?? .auto
        let extractor = AudioExtractor(verbose: common.verbose)
        let (wavPath, _, _) = try await extractor.extract(
            from: common.inputFile,
            preprocess: preprocessMode
        )
        tempFiles.append(wavPath)

        // Step 2: Transcribe
        print("Transcribing...")
        let transcriber = Transcriber(model: whisperModel, verbose: common.verbose)
        var segments = try await transcriber.transcribe(wavPath: wavPath)

        // Step 3: Diarize (optional)
        if hasSpeakers {
            print("Identifying speakers...")
            let speakerNames = common.parseSpeakerNames()
            let deviceMode = common.device
            let diarizer = Diarizer(verbose: common.verbose, speakerNames: speakerNames, device: deviceMode)
            segments = try await diarizer.diarize(wavPath: wavPath, segments: segments)
        }

        // Step 4: Write output
        if resolvedFormat.requiresPandoc {
            // Pandoc path: generate markdown first, then convert
            let tempMdPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).md").path
            tempFiles.append(tempMdPath)

            let mdWriter = TextWriter(format: .md, includeTimestamps: timestamps)
            try mdWriter.write(segments: segments, to: tempMdPath)

            print("Converting to \(resolvedFormat.rawValue)...")
            try PandocConverter.convert(from: tempMdPath, to: outputPath, format: resolvedFormat)
        } else {
            print("Writing \(resolvedFormat.rawValue)...")
            let writer = TextWriter(format: resolvedFormat, includeTimestamps: timestamps)
            try writer.write(segments: segments, to: outputPath)
        }

        print("Output written to: \(outputPath)")
    }

    /// Resolve format from: explicit flag > output extension > default (txt).
    private func resolveFormat() -> TextWriter.Format {
        // Explicit --format flag
        if let explicit = format,
           let fmt = TextWriter.Format(rawValue: explicit.lowercased()) {
            return fmt
        }

        // Deduce from --output extension
        if let outputArg = common.output,
           let deduced = TextWriter.deduceFormat(from: outputArg) {
            return deduced
        }

        return .txt
    }
}
