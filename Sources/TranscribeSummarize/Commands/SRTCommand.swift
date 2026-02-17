// ABOUTME: Subcommand to generate SRT subtitle files from audio/video.
// ABOUTME: Uses whisper-cli native output or custom SRTWriter for diarized output.

import ArgumentParser
import Foundation

struct SRTCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "srt",
        abstract: "Generate SRT subtitles from audio/video."
    )

    @OptionGroup var common: CommonOptions

    mutating func run() async throws {
        guard common.validateInput() else {
            throw ExitCode.validationFailure
        }

        let outputPath = common.resolveOutputPath(defaultExtension: "srt")
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
            // Diarized path: transcribe → diarize → custom SRTWriter
            print("Transcribing...")
            var segments = try await transcriber.transcribe(wavPath: wavPath)

            print("Identifying speakers...")
            let speakerNames = common.parseSpeakerNames()
            let deviceMode = common.device
            let diarizer = Diarizer(verbose: common.verbose, speakerNames: speakerNames, device: deviceMode)
            segments = try await diarizer.diarize(wavPath: wavPath, segments: segments)

            print("Writing SRT...")
            let writer = SRTWriter()
            try writer.write(segments: segments, to: outputPath)
        } else {
            // Fast path: let whisper-cli write SRT directly
            print("Transcribing to SRT...")
            let tempBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let srtPath = try await transcriber.transcribeDirect(
                wavPath: wavPath,
                format: .srt,
                outputBase: tempBase
            )
            tempFiles.append(srtPath)
            try FileManager.default.copyItem(atPath: srtPath, toPath: outputPath)
        }

        print("Output written to: \(outputPath)")
    }
}
