// ABOUTME: Subcommand to generate WebVTT subtitle files from audio/video.
// ABOUTME: Uses whisper-cli native output or custom VTTWriter for diarized output.

import ArgumentParser
import Foundation

struct VTTCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vtt",
        abstract: "Generate WebVTT subtitles from audio/video."
    )

    @OptionGroup var common: CommonOptions

    mutating func run() async throws {
        guard common.validateInput() else {
            throw ExitCode.validationFailure
        }

        let outputPath = common.resolveOutputPath(defaultExtension: "vtt")
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

        let transcriberModel = Transcriber.Model(rawValue: whisperModel.rawValue) ?? .small
        let transcriber = Transcriber(model: transcriberModel, verbose: common.verbose)

        if hasSpeakers {
            // Diarized path: transcribe → diarize → custom VTTWriter
            print("Transcribing...")
            var segments = try await transcriber.transcribe(wavPath: wavPath)

            print("Identifying speakers...")
            let speakerNames = common.parseSpeakerNames()
            let deviceMode = common.device
            let diarizer = Diarizer(verbose: common.verbose, speakerNames: speakerNames, device: deviceMode)
            segments = try await diarizer.diarize(wavPath: wavPath, segments: segments)

            print("Writing VTT...")
            let writer = VTTWriter()
            try writer.write(segments: segments, to: outputPath)
        } else {
            // Fast path: let whisper-cli write VTT directly
            print("Transcribing to VTT...")
            let tempBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let vttPath = try await transcriber.transcribeDirect(
                wavPath: wavPath,
                format: .vtt,
                outputBase: tempBase
            )
            tempFiles.append(vttPath)
            try FileManager.default.copyItem(atPath: vttPath, toPath: outputPath)
        }

        print("Output written to: \(outputPath)")
    }
}
