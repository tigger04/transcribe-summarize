// ABOUTME: Unit tests for markdown output generation.
// ABOUTME: Tests formatting, confidence flags, structure.

import XCTest
@testable import TranscribeSummarize

final class MarkdownWriterTests: XCTestCase {

    func testConfidenceRatingExcellent() {
        let segments = [
            Segment(start: 0, end: 5, text: "Hello", speaker: nil, confidence: 0.98),
            Segment(start: 5, end: 10, text: "World", speaker: nil, confidence: 0.96),
        ]

        let rating = MarkdownWriter.calculateConfidenceRating(segments: segments)
        XCTAssertEqual(rating, "97% (Excellent)")
    }

    func testConfidenceRatingGood() {
        let segments = [
            Segment(start: 0, end: 5, text: "Hello", speaker: nil, confidence: 0.90),
            Segment(start: 5, end: 10, text: "World", speaker: nil, confidence: 0.88),
        ]

        let rating = MarkdownWriter.calculateConfidenceRating(segments: segments)
        XCTAssertEqual(rating, "89% (Good)")
    }

    func testConfidenceRatingFair() {
        let segments = [
            Segment(start: 0, end: 5, text: "Hello", speaker: nil, confidence: 0.75),
            Segment(start: 5, end: 10, text: "World", speaker: nil, confidence: 0.77),
        ]

        let rating = MarkdownWriter.calculateConfidenceRating(segments: segments)
        XCTAssertEqual(rating, "76% (Fair)")
    }

    func testConfidenceRatingPoor() {
        let segments = [
            Segment(start: 0, end: 5, text: "Hello", speaker: nil, confidence: 0.50),
            Segment(start: 5, end: 10, text: "World", speaker: nil, confidence: 0.60),
        ]

        let rating = MarkdownWriter.calculateConfidenceRating(segments: segments)
        XCTAssertEqual(rating, "55% (Poor)")
    }

    func testConfidenceRatingEmpty() {
        let rating = MarkdownWriter.calculateConfidenceRating(segments: [])
        XCTAssertEqual(rating, "N/A")
    }

    func testDurationFormattingShort() {
        XCTAssertEqual(MarkdownWriter.formatDuration(45), "0:45")
        XCTAssertEqual(MarkdownWriter.formatDuration(65), "1:05")
        XCTAssertEqual(MarkdownWriter.formatDuration(600), "10:00")
    }

    func testDurationFormattingLong() {
        XCTAssertEqual(MarkdownWriter.formatDuration(3600), "1:00:00")
        XCTAssertEqual(MarkdownWriter.formatDuration(3661), "1:01:01")
        XCTAssertEqual(MarkdownWriter.formatDuration(7325), "2:02:05")
    }

    func testDefaultTitleFromSnakeCase() {
        XCTAssertEqual(
            MarkdownWriter.defaultTitle(from: "/path/to/weekly_standup.m4a"),
            "Weekly Standup"
        )
    }

    func testDefaultTitleFromKebabCase() {
        XCTAssertEqual(
            MarkdownWriter.defaultTitle(from: "/path/to/team-meeting.mp4"),
            "Team Meeting"
        )
    }

    func testDefaultTitleSimple() {
        XCTAssertEqual(
            MarkdownWriter.defaultTitle(from: "recording.wav"),
            "Recording"
        )
    }
}
