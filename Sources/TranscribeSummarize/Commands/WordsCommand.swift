// ABOUTME: Subcommand to generate word-by-word JSON with per-word timestamps.
// ABOUTME: Uses whisper-cli --output-json-full with --dtw for token-level timing.

import ArgumentParser
import Foundation

struct WordsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "words",
        abstract: "Generate word-by-word JSON with per-word timestamps."
    )

    @OptionGroup var common: CommonOptions

    mutating func run() async throws {
        guard common.validateInput() else {
            throw ExitCode.validationFailure
        }

        let outputPath = common.resolveOutputPath(defaultExtension: "json")
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

        // Generate word-level JSON via whisper-cli
        print("Transcribing to word-level JSON...")
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let jsonPath = try await transcriber.transcribeDirect(
            wavPath: wavPath,
            format: .jsonFull,
            outputBase: tempBase
        )
        tempFiles.append(jsonPath)

        if hasSpeakers {
            // Post-process: merge speaker labels into the word-level JSON
            print("Identifying speakers...")
            let segments = try await transcriber.transcribe(wavPath: wavPath)
            let speakerNames = common.parseSpeakerNames()
            let deviceMode = common.device
            let diarizer = Diarizer(verbose: common.verbose, speakerNames: speakerNames, device: deviceMode)
            let diarizedSegments = try await diarizer.diarize(wavPath: wavPath, segments: segments)

            print("Merging speaker labels...")
            try mergeSpakersIntoJSON(
                jsonPath: jsonPath,
                segments: diarizedSegments,
                outputPath: outputPath
            )
        } else {
            try FileManager.default.copyItem(atPath: jsonPath, toPath: outputPath)
        }

        print("Output written to: \(outputPath)")
    }

    /// Merge speaker labels from diarized segments into whisper-cli full JSON output.
    /// Adds a "speaker" field to each token based on its timestamp.
    private func mergeSpakersIntoJSON(
        jsonPath: String,
        segments: [Segment],
        outputPath: String
    ) throws {
        guard let data = FileManager.default.contents(atPath: jsonPath),
              var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var transcription = json["transcription"] as? [[String: Any]] else {
            // If we can't parse, just copy the original
            try FileManager.default.copyItem(atPath: jsonPath, toPath: outputPath)
            return
        }

        for i in 0..<transcription.count {
            guard let offsets = transcription[i]["offsets"] as? [String: Any],
                  let fromMs = offsets["from"] as? Int else {
                continue
            }
            let timeSeconds = Double(fromMs) / 1000.0
            let speaker = findSpeaker(at: timeSeconds, in: segments)
            transcription[i]["speaker"] = speaker
        }

        json["transcription"] = transcription
        let outputData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: outputPath))
    }

    /// Find which speaker is talking at a given timestamp.
    private func findSpeaker(at time: Double, in segments: [Segment]) -> String? {
        for segment in segments {
            if time >= segment.start && time <= segment.end {
                return segment.speaker
            }
        }
        return nil
    }
}
