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
            model: "",  // Empty = no CLI override, should use default
            llm: "auto",
            preprocess: "auto",
            device: "auto",
            verbose: 0,
            dryRun: true
        )

        // Default model should be small (not base) for better accent handling
        XCTAssertEqual(config.model, .small, "Default model should be 'small' for better accent handling")
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

    // MARK: - Whisper Args Tests

    func testTranscriberWhisperArgsDefaultNoMaxLen() {
        let transcriber = Transcriber(model: .tiny, verbose: 0)
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
        let transcriber = Transcriber(model: .tiny, verbose: 0)
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
        let transcriber = Transcriber(model: .tiny, verbose: 0)
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
        let transcriber = Transcriber(model: .tiny, verbose: 0)
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

    // MARK: - Helper

    /// Mirrors the output path resolution logic used by subcommands.
    private func outputPath(for input: String, extension ext: String) -> String {
        let url = URL(fileURLWithPath: input)
        return url.deletingPathExtension().appendingPathExtension(ext).path
    }
}
