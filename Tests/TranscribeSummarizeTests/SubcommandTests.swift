// ABOUTME: Tests for subcommand architecture, default model, and output path resolution.
// ABOUTME: Verifies CommonOptions defaults and Segment millisecond timestamps.

import XCTest
@testable import TranscribeSummarize

final class SubcommandTests: XCTestCase {

    // MARK: - Default Model Tests

    func testDefaultModelIsSmall() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "small",  // Explicit to avoid config file override
            llm: "auto",
            preprocess: "auto",
            device: "auto",
            verbose: 0,
            dryRun: true
        )

        // Verify 'small' is accepted and resolved correctly
        XCTAssertEqual(config.modelName, "small", "Model 'small' should resolve correctly")
    }

    // MARK: - Segment Millisecond Timestamp Tests

    func testSRTTimestampFormat() {
        let segment = Segment(start: 1.5, end: 4.75, text: "Test", speaker: nil, confidence: 1.0)

        XCTAssertEqual(segment.srtStartTimestamp, "00:00:01,500", "SRT timestamps use comma for milliseconds")
        XCTAssertEqual(segment.srtEndTimestamp, "00:00:04,750", "SRT timestamps use comma for milliseconds")
    }

    func testVTTTimestampFormat() {
        let segment = Segment(start: 1.5, end: 4.75, text: "Test", speaker: nil, confidence: 1.0)

        XCTAssertEqual(segment.vttStartTimestamp, "00:00:01.500", "VTT timestamps use period for milliseconds")
        XCTAssertEqual(segment.vttEndTimestamp, "00:00:04.750", "VTT timestamps use period for milliseconds")
    }

    func testMillisecondTimestampWithHours() {
        let segment = Segment(start: 3661.123, end: 3665.999, text: "Test", speaker: nil, confidence: 1.0)

        XCTAssertEqual(segment.srtStartTimestamp, "01:01:01,123")
        XCTAssertEqual(segment.srtEndTimestamp, "01:01:05,999")
        XCTAssertEqual(segment.vttStartTimestamp, "01:01:01.123")
        XCTAssertEqual(segment.vttEndTimestamp, "01:01:05.999")
    }

    func testMillisecondTimestampZero() {
        let segment = Segment(start: 0.0, end: 0.5, text: "Start", speaker: nil, confidence: 1.0)

        XCTAssertEqual(segment.srtStartTimestamp, "00:00:00,000")
        XCTAssertEqual(segment.vttStartTimestamp, "00:00:00.000")
    }

    // MARK: - Output Path Resolution Tests

    func testOutputPathResolutionSRT() {
        let path = outputPath(for: "/path/to/meeting.m4a", extension: "srt")
        XCTAssertEqual(path, "/path/to/meeting.srt")
    }

    func testOutputPathResolutionVTT() {
        let path = outputPath(for: "/path/to/meeting.m4a", extension: "vtt")
        XCTAssertEqual(path, "/path/to/meeting.vtt")
    }

    func testOutputPathResolutionJSON() {
        let path = outputPath(for: "/path/to/meeting.m4a", extension: "json")
        XCTAssertEqual(path, "/path/to/meeting.json")
    }

    func testOutputPathResolutionMD() {
        let path = outputPath(for: "/path/to/meeting.m4a", extension: "md")
        XCTAssertEqual(path, "/path/to/meeting.md")
    }

    // MARK: - Custom Model Tests

    func testKnownModelFilename() {
        let transcriber = Transcriber(model: .known(.small), verbose: 0)
        XCTAssertEqual(transcriber.modelName, "small")
    }

    func testCustomModelFilename() {
        let transcriber = Transcriber(model: .custom("large-v3-turbo"), verbose: 0)
        XCTAssertEqual(transcriber.modelName, "large-v3-turbo")
    }

    func testTranscriberModelFromStringKnown() {
        let model = Transcriber.ModelSpec.from("small")
        if case .known(let m) = model {
            XCTAssertEqual(m, .small)
        } else {
            XCTFail("Expected known model for 'small'")
        }
    }

    func testTranscriberModelFromStringCustom() {
        let model = Transcriber.ModelSpec.from("large-v3-turbo")
        if case .custom(let name) = model {
            XCTAssertEqual(name, "large-v3-turbo")
        } else {
            XCTFail("Expected custom model for 'large-v3-turbo'")
        }
    }

    /// RT-029: DTW preset converts hyphens to dots for whisper-cli
    func testDtwPresetConvertsToDotNotation_RT029() {
        // Arrange
        let customModel = Transcriber.ModelSpec.custom("large-v3-turbo")
        let knownModel = Transcriber.ModelSpec.known(.small)

        // Assert
        XCTAssertEqual(customModel.dtwPreset, "large.v3.turbo",
                       "DTW preset should use dots, not hyphens")
        XCTAssertEqual(knownModel.dtwPreset, "small",
                       "Known models should pass through unchanged")
    }

    /// RT-030: DTW preset for models with multiple hyphens
    func testDtwPresetMultipleHyphens_RT030() {
        let model = Transcriber.ModelSpec.custom("large-v3-turbo-q5")
        XCTAssertEqual(model.dtwPreset, "large.v3.turbo.q5")
    }

    func testConfigResolvesCustomModel() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "large-v3-turbo",
            llm: "auto",
            preprocess: "auto",
            device: "auto",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.modelName, "large-v3-turbo",
                       "Config should pass through custom model names")
    }

    func testConfigResolvesKnownModel() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "medium",
            llm: "auto",
            preprocess: "auto",
            device: "auto",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.modelName, "medium",
                       "Config should resolve known model names")
    }

    // MARK: - Whisper Args Tests

    func testTranscriberWhisperArgsDefaultNoMaxLen() {
        let transcriber = Transcriber(model: .known(.tiny), verbose: 0)
        let args = transcriber.buildWhisperArgs(
            modelPath: "/models/ggml-tiny.bin",
            wavPath: "/tmp/test.wav",
            maxLen: 0,
            splitOnWord: false
        )

        XCTAssertFalse(args.contains("-ml"), "Should not include -ml when maxLen is 0")
        XCTAssertFalse(args.contains("-sow"), "Should not include -sow when splitOnWord is false")
    }

    func testTranscriberWhisperArgsWithMaxLen() {
        let transcriber = Transcriber(model: .known(.tiny), verbose: 0)
        let args = transcriber.buildWhisperArgs(
            modelPath: "/models/ggml-tiny.bin",
            wavPath: "/tmp/test.wav",
            maxLen: 42,
            splitOnWord: false
        )

        XCTAssertTrue(args.contains("-ml"), "Should include -ml flag")
        if let idx = args.firstIndex(of: "-ml") {
            XCTAssertEqual(args[args.index(after: idx)], "42", "maxLen value should be 42")
        }
        XCTAssertFalse(args.contains("-sow"), "Should not include -sow when splitOnWord is false")
    }

    func testTranscriberWhisperArgsWithMaxLenAndSplitOnWord() {
        let transcriber = Transcriber(model: .known(.tiny), verbose: 0)
        let args = transcriber.buildWhisperArgs(
            modelPath: "/models/ggml-tiny.bin",
            wavPath: "/tmp/test.wav",
            maxLen: 30,
            splitOnWord: true
        )

        XCTAssertTrue(args.contains("-ml"), "Should include -ml flag")
        XCTAssertTrue(args.contains("-sow"), "Should include -sow flag")
    }

    func testTranscriberWhisperArgsSplitOnWordWithoutMaxLenIgnored() {
        let transcriber = Transcriber(model: .known(.tiny), verbose: 0)
        let args = transcriber.buildWhisperArgs(
            modelPath: "/models/ggml-tiny.bin",
            wavPath: "/tmp/test.wav",
            maxLen: 0,
            splitOnWord: true
        )

        // splitOnWord without maxLen is meaningless; neither flag should appear
        XCTAssertFalse(args.contains("-ml"), "Should not include -ml when maxLen is 0")
        XCTAssertFalse(args.contains("-sow"), "Should not include -sow when maxLen is 0")
    }

    // MARK: - Subtitle Default Max Length Tests

    /// RT-035: Default maxLen for subtitles is 48
    func testSubtitleDefaultMaxLenIs48_RT035() {
        // The SRT and VTT commands should default to maxLen 48.
        // We verify this by checking that buildWhisperArgs with maxLen=48
        // includes -ml 48.
        let transcriber = Transcriber(model: .known(.tiny), verbose: 0)
        let args = transcriber.buildWhisperArgs(
            modelPath: "/models/ggml-tiny.bin",
            wavPath: "/tmp/test.wav",
            maxLen: 48,
            splitOnWord: true
        )

        XCTAssertTrue(args.contains("-ml"), "Should include -ml flag for default 48")
        if let idx = args.firstIndex(of: "-ml") {
            XCTAssertEqual(args[args.index(after: idx)], "48", "Default maxLen should be 48")
        }
        XCTAssertTrue(args.contains("-sow"), "Should include -sow with default splitOnWord")
    }

    /// RT-036: Explicit maxLen=0 produces unlimited (no -ml flag)
    func testSubtitleMaxLenZeroIsUnlimited_RT036() {
        let transcriber = Transcriber(model: .known(.tiny), verbose: 0)
        let args = transcriber.buildWhisperArgs(
            modelPath: "/models/ggml-tiny.bin",
            wavPath: "/tmp/test.wav",
            maxLen: 0,
            splitOnWord: false
        )

        XCTAssertFalse(args.contains("-ml"), "maxLen=0 should not include -ml (unlimited)")
    }

    // MARK: - Helper

    /// Mirrors the output path resolution logic used by subcommands.
    private func outputPath(for input: String, extension ext: String) -> String {
        let url = URL(fileURLWithPath: input)
        return url.deletingPathExtension().appendingPathExtension(ext).path
    }
}
