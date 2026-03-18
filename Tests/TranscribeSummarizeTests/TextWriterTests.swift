// ABOUTME: Tests for TextWriter plain text and markdown transcript output.
// ABOUTME: Covers formatting, timestamps, speakers, and format deduction from output path.

import XCTest
@testable import TranscribeSummarize

final class TextWriterTests: XCTestCase {

    let sampleSegments = [
        Segment(start: 1.0, end: 3.0, text: "Welcome everyone.", speaker: "Alice", confidence: 0.95),
        Segment(start: 4.0, end: 7.0, text: "Thanks for coming.", speaker: "Bob", confidence: 0.90),
        Segment(start: 8.0, end: 11.0, text: "Let's begin.", speaker: "Alice", confidence: 0.88),
    ]

    let noSpeakerSegments = [
        Segment(start: 1.0, end: 3.0, text: "Welcome everyone.", speaker: nil, confidence: 0.95),
        Segment(start: 4.0, end: 7.0, text: "Thanks for coming.", speaker: nil, confidence: 0.90),
    ]

    // MARK: - Plain Text Format (RT-015, RT-019)

    /// RT-015: Plain text output has one segment per line
    func testPlainTextBasicFormat_RT015() {
        // Arrange
        let writer = TextWriter(format: .txt, includeTimestamps: false)

        // Act
        let output = writer.generate(segments: sampleSegments)

        // Assert
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3, "Should have one line per segment")
        XCTAssertTrue(lines[0].contains("Welcome everyone."))
        XCTAssertTrue(lines[1].contains("Thanks for coming."))
        XCTAssertTrue(lines[2].contains("Let's begin."))
    }

    /// RT-019: No speaker prefix without speakers
    func testPlainTextNoSpeakerPrefix_RT019() {
        // Arrange
        let writer = TextWriter(format: .txt, includeTimestamps: false)

        // Act
        let output = writer.generate(segments: noSpeakerSegments)

        // Assert
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines {
            XCTAssertFalse(line.contains(":"), "No speaker prefix should appear: \(line)")
        }
    }

    // MARK: - Speaker Labels (RT-016)

    /// RT-016: Speaker names prefix each line
    func testPlainTextWithSpeakers_RT016() {
        // Arrange
        let writer = TextWriter(format: .txt, includeTimestamps: false)

        // Act
        let output = writer.generate(segments: sampleSegments)

        // Assert
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertTrue(lines[0].hasPrefix("Alice: "), "First line should start with 'Alice: '")
        XCTAssertTrue(lines[1].hasPrefix("Bob: "), "Second line should start with 'Bob: '")
    }

    // MARK: - Timestamps (RT-017)

    /// RT-017: Timestamps prefix each line
    func testPlainTextWithTimestamps_RT017() {
        // Arrange
        let writer = TextWriter(format: .txt, includeTimestamps: true)

        // Act
        let output = writer.generate(segments: sampleSegments)

        // Assert
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertTrue(lines[0].hasPrefix("[00:00:01]"), "First line should start with timestamp")
        XCTAssertTrue(lines[1].hasPrefix("[00:00:04]"), "Second line should start with timestamp")
    }

    func testPlainTextWithTimestampsAndSpeakers() {
        // Arrange
        let writer = TextWriter(format: .txt, includeTimestamps: true)

        // Act
        let output = writer.generate(segments: sampleSegments)

        // Assert: format is [HH:MM:SS] Speaker: text
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines[0], "[00:00:01] Alice: Welcome everyone.")
        XCTAssertEqual(lines[1], "[00:00:04] Bob: Thanks for coming.")
    }

    // MARK: - Markdown Format (RT-018)

    /// RT-018: Markdown uses bold speakers and paragraph separation
    func testMarkdownFormat_RT018() {
        // Arrange
        let writer = TextWriter(format: .md, includeTimestamps: false)

        // Act
        let output = writer.generate(segments: sampleSegments)

        // Assert: bold speakers, double-newline separation
        XCTAssertTrue(output.contains("**Alice:** Welcome everyone."),
                      "Markdown should use bold speaker names")
        XCTAssertTrue(output.contains("**Bob:** Thanks for coming."),
                      "Markdown should use bold speaker names")
        XCTAssertTrue(output.contains("\n\n"), "Markdown should have paragraph breaks")
    }

    func testMarkdownWithoutSpeakers() {
        // Arrange
        let writer = TextWriter(format: .md, includeTimestamps: false)

        // Act
        let output = writer.generate(segments: noSpeakerSegments)

        // Assert
        XCTAssertFalse(output.contains("**"), "No bold formatting without speakers")
        XCTAssertTrue(output.contains("Welcome everyone."))
    }

    // MARK: - Write to File (RT-021)

    /// RT-021: Output written to specified path
    func testWriteToFile_RT021() throws {
        // Arrange
        let writer = TextWriter(format: .txt, includeTimestamps: false)
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_output_\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        // Act
        try writer.write(segments: sampleSegments, to: tempPath)

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath),
                      "File should be written to specified path")
        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("Welcome everyone."))
    }

    // MARK: - Format Deduction from Extension (RT-022)

    /// RT-022: Format deduced from output path extension
    func testFormatDeductionFromExtension_RT022() {
        XCTAssertEqual(TextWriter.deduceFormat(from: "/tmp/notes.md"), .md)
        XCTAssertEqual(TextWriter.deduceFormat(from: "/tmp/notes.txt"), .txt)
        XCTAssertEqual(TextWriter.deduceFormat(from: "/tmp/notes.docx"), .docx)
        XCTAssertEqual(TextWriter.deduceFormat(from: "/tmp/notes.odt"), .odt)
        XCTAssertEqual(TextWriter.deduceFormat(from: "/tmp/notes.html"), .html)
        XCTAssertEqual(TextWriter.deduceFormat(from: "/tmp/notes.pdf"), .pdf)
        XCTAssertNil(TextWriter.deduceFormat(from: "/tmp/notes.xyz"),
                     "Unknown extension should return nil")
    }

    // MARK: - Empty Segments

    func testEmptySegmentsProducesEmptyOutput() {
        let writer = TextWriter(format: .txt, includeTimestamps: false)
        let output = writer.generate(segments: [])
        XCTAssertTrue(output.isEmpty, "Empty segments should produce empty output")
    }
}
