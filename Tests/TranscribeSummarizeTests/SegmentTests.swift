// ABOUTME: Unit tests for Segment model.
// ABOUTME: Tests timestamp formatting.

import XCTest
@testable import TranscribeSummarize

final class SegmentTests: XCTestCase {

    func testTimestampFormatting() {
        let segment = Segment(
            start: 3661.5,
            end: 3665.0,
            text: "Hello",
            speaker: nil,
            confidence: 0.95
        )

        XCTAssertEqual(segment.startTimestamp, "01:01:01")
        XCTAssertEqual(segment.endTimestamp, "01:01:05")
    }

    func testShortTimestamp() {
        let segment = Segment(
            start: 65.0,
            end: 70.0,
            text: "Hello",
            speaker: nil,
            confidence: 0.95
        )

        XCTAssertEqual(segment.startTimestamp, "00:01:05")
        XCTAssertEqual(segment.endTimestamp, "00:01:10")
    }

    func testZeroTimestamp() {
        let segment = Segment(
            start: 0.0,
            end: 5.0,
            text: "Start",
            speaker: "Speaker 1",
            confidence: 1.0
        )

        XCTAssertEqual(segment.startTimestamp, "00:00:00")
        XCTAssertEqual(segment.endTimestamp, "00:00:05")
    }
}
