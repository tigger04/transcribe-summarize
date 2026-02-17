// ABOUTME: Unit tests for WebVTT subtitle output generation.
// ABOUTME: Tests formatting with and without voice spans.

import XCTest
@testable import TranscribeSummarize

final class VTTWriterTests: XCTestCase {

    private let segments = [
        Segment(start: 1.0, end: 4.5, text: "Welcome to the meeting.", speaker: nil, confidence: 0.95),
        Segment(start: 5.2, end: 8.1, text: "Thanks, let's get started.", speaker: nil, confidence: 0.90),
    ]

    private let diarizedSegments = [
        Segment(start: 1.0, end: 4.5, text: "Welcome to the meeting.", speaker: "Alice", confidence: 0.95),
        Segment(start: 5.2, end: 8.1, text: "Thanks, let's get started.", speaker: "Bob", confidence: 0.90),
    ]

    // MARK: - VTT Format Tests

    func testVTTFormatWithoutSpeakers() throws {
        let writer = VTTWriter()
        let output = writer.generate(segments: segments)

        // Verify VTT header
        XCTAssertTrue(output.hasPrefix("WEBVTT\n"), "Should start with WEBVTT header")

        // Verify VTT timestamp format (period for milliseconds)
        XCTAssertTrue(output.contains("00:00:01.000 --> 00:00:04.500"), "Should have correct VTT timestamps")
        XCTAssertTrue(output.contains("00:00:05.200 --> 00:00:08.100"), "Should have correct VTT timestamps")

        // Verify text content
        XCTAssertTrue(output.contains("Welcome to the meeting."), "Should contain segment text")

        // Verify no voice spans when no speakers
        XCTAssertFalse(output.contains("<v"), "Should not have voice spans without speakers")
    }

    func testVTTFormatWithSpeakers() throws {
        let writer = VTTWriter()
        let output = writer.generate(segments: diarizedSegments)

        // Verify VTT voice spans per WebVTT spec
        XCTAssertTrue(output.contains("<v Alice>Welcome to the meeting.</v>"), "Should have voice span for Alice")
        XCTAssertTrue(output.contains("<v Bob>Thanks, let's get started.</v>"), "Should have voice span for Bob")
    }

    func testVTTWriteToFile() throws {
        let writer = VTTWriter()
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".vtt").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try writer.write(segments: segments, to: tempPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), "VTT file should exist")

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("WEBVTT\n"), "Written file should have WEBVTT header")
        XCTAssertTrue(content.contains("Welcome to the meeting."), "Written file should have text")
    }

    func testVTTTimestampPrecision() throws {
        let segments = [
            Segment(start: 3661.123, end: 3665.999, text: "Test", speaker: nil, confidence: 1.0),
        ]
        let writer = VTTWriter()
        let output = writer.generate(segments: segments)

        XCTAssertTrue(output.contains("01:01:01.123 --> 01:01:05.999"), "Should format hours and milliseconds correctly")
    }

    func testVTTEmptySegments() throws {
        let writer = VTTWriter()
        let output = writer.generate(segments: [])

        // Even with no segments, should have the WEBVTT header
        XCTAssertTrue(output.hasPrefix("WEBVTT\n"), "Should still have WEBVTT header")
    }
}
