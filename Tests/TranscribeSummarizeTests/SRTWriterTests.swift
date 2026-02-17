// ABOUTME: Unit tests for SRT subtitle output generation.
// ABOUTME: Tests formatting with and without speaker labels.

import XCTest
@testable import TranscribeSummarize

final class SRTWriterTests: XCTestCase {

    private let segments = [
        Segment(start: 1.0, end: 4.5, text: "Welcome to the meeting.", speaker: nil, confidence: 0.95),
        Segment(start: 5.2, end: 8.1, text: "Thanks, let's get started.", speaker: nil, confidence: 0.90),
        Segment(start: 10.0, end: 15.75, text: "First item on the agenda.", speaker: nil, confidence: 0.85),
    ]

    private let diarizedSegments = [
        Segment(start: 1.0, end: 4.5, text: "Welcome to the meeting.", speaker: "Alice", confidence: 0.95),
        Segment(start: 5.2, end: 8.1, text: "Thanks, let's get started.", speaker: "Bob", confidence: 0.90),
    ]

    // MARK: - SRT Format Tests

    func testSRTFormatWithoutSpeakers() throws {
        let writer = SRTWriter()
        let output = writer.generate(segments: segments)

        // Verify sequence numbers
        XCTAssertTrue(output.contains("1\n"), "Should have sequence number 1")
        XCTAssertTrue(output.contains("2\n"), "Should have sequence number 2")
        XCTAssertTrue(output.contains("3\n"), "Should have sequence number 3")

        // Verify SRT timestamp format (comma for milliseconds)
        XCTAssertTrue(output.contains("00:00:01,000 --> 00:00:04,500"), "Should have correct SRT timestamps")
        XCTAssertTrue(output.contains("00:00:05,200 --> 00:00:08,100"), "Should have correct SRT timestamps")

        // Verify text content
        XCTAssertTrue(output.contains("Welcome to the meeting."), "Should contain segment text")

        // Verify no speaker labels when no speakers
        XCTAssertFalse(output.contains("["), "Should not have speaker brackets without speakers")
    }

    func testSRTFormatWithSpeakers() throws {
        let writer = SRTWriter()
        let output = writer.generate(segments: diarizedSegments)

        // Verify speaker labels
        XCTAssertTrue(output.contains("[Alice]: Welcome to the meeting."), "Should have speaker label for Alice")
        XCTAssertTrue(output.contains("[Bob]: Thanks, let's get started."), "Should have speaker label for Bob")
    }

    func testSRTWriteToFile() throws {
        let writer = SRTWriter()
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".srt").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try writer.write(segments: segments, to: tempPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), "SRT file should exist")

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("1\n"), "Written file should have sequence numbers")
        XCTAssertTrue(content.contains("Welcome to the meeting."), "Written file should have text")
    }

    func testSRTTimestampPrecision() throws {
        let segments = [
            Segment(start: 3661.123, end: 3665.999, text: "Test", speaker: nil, confidence: 1.0),
        ]
        let writer = SRTWriter()
        let output = writer.generate(segments: segments)

        XCTAssertTrue(output.contains("01:01:01,123 --> 01:01:05,999"), "Should format hours and milliseconds correctly")
    }

    func testSRTEmptySegments() throws {
        let writer = SRTWriter()
        let output = writer.generate(segments: [])

        XCTAssertTrue(output.isEmpty, "Empty segments should produce empty output")
    }
}
