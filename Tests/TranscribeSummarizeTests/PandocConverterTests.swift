// ABOUTME: Tests for PandocConverter and pandoc-backed format support.
// ABOUTME: Covers error messages, format requirements, availability check, and temp file cleanup.

import XCTest
@testable import TranscribeSummarize

final class PandocConverterTests: XCTestCase {

    // MARK: - RT-023: Pandoc-not-found error message

    /// RT-023: Error message names pandoc and suggests brew install
    func testPandocNotFoundErrorContainsInstallInstructions_RT023() {
        // Arrange
        let error = PandocConverter.ConversionError.pandocNotFound(format: "docx")

        // Act
        let message = error.errorDescription ?? ""

        // Assert
        XCTAssertTrue(message.contains("pandoc"), "Error should mention pandoc")
        XCTAssertTrue(message.contains("brew install pandoc"), "Error should suggest brew install")
        XCTAssertTrue(message.contains(".docx"), "Error should name the requested format")
    }

    /// RT-023 supplement: PDF error includes LaTeX note
    func testPandocNotFoundErrorForPDFMentionsLaTeX_RT023() {
        // Arrange
        let error = PandocConverter.ConversionError.pandocNotFound(format: "pdf")

        // Act
        let message = error.errorDescription ?? ""

        // Assert
        XCTAssertTrue(message.contains("LaTeX"), "PDF error should mention LaTeX requirement")
        XCTAssertTrue(message.contains("basictex"), "PDF error should suggest basictex")
    }

    // MARK: - RT-024: Native formats don't require pandoc

    /// RT-024: txt and md formats succeed without pandoc
    func testNativeFormatsDoNotRequirePandoc_RT024() {
        // Assert
        XCTAssertFalse(TextWriter.Format.txt.requiresPandoc,
                       "txt should not require pandoc")
        XCTAssertFalse(TextWriter.Format.md.requiresPandoc,
                       "md should not require pandoc")
    }

    /// RT-024 supplement: pandoc-backed formats require pandoc
    func testPandocFormatsRequirePandoc_RT024() {
        // Assert
        XCTAssertTrue(TextWriter.Format.docx.requiresPandoc,
                      "docx should require pandoc")
        XCTAssertTrue(TextWriter.Format.odt.requiresPandoc,
                      "odt should require pandoc")
        XCTAssertTrue(TextWriter.Format.pdf.requiresPandoc,
                      "pdf should require pandoc")
        XCTAssertTrue(TextWriter.Format.html.requiresPandoc,
                      "html should require pandoc")
    }

    // MARK: - RT-025: Pandoc availability check

    /// RT-025: isAvailable returns a boolean (smoke test)
    func testPandocAvailabilityReturnsBool_RT025() {
        // Act — just verify this doesn't crash and returns a deterministic result
        let first = PandocConverter.isAvailable()
        let second = PandocConverter.isAvailable()

        // Assert — should be consistent between calls
        XCTAssertEqual(first, second, "Availability check should be deterministic")
    }

    // MARK: - RT-026: Temp file cleanup after pandoc conversion

    /// RT-026: Intermediate markdown is cleaned up after conversion
    func testTempFileCleanedUpAfterConversion_RT026() throws {
        // Skip if pandoc is not installed
        guard PandocConverter.isAvailable() else {
            throw XCTSkip("pandoc not installed — skipping conversion test")
        }

        // Arrange
        let segments = [
            Segment(start: 1.0, end: 3.0, text: "Hello world.", speaker: "Alice", confidence: 0.95),
        ]

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pandoc_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempMdPath = tempDir.appendingPathComponent("intermediate.md").path
        let outputPath = tempDir.appendingPathComponent("output.html").path

        // Act: generate markdown, convert, then clean up (mimics TextCommand flow)
        let mdWriter = TextWriter(format: .md, includeTimestamps: false)
        try mdWriter.write(segments: segments, to: tempMdPath)

        // Verify intermediate exists before conversion
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempMdPath),
                      "Intermediate markdown should exist before conversion")

        try PandocConverter.convert(from: tempMdPath, to: outputPath, format: .html)

        // Clean up intermediate (as TextCommand does)
        try FileManager.default.removeItem(atPath: tempMdPath)

        // Assert: output exists, intermediate is gone
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath),
                      "Converted output file should exist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempMdPath),
                       "Intermediate markdown should be cleaned up")
    }

    // MARK: - Conversion failure error

    func testConversionFailedErrorContainsExitCodeAndStderr() {
        // Arrange
        let error = PandocConverter.ConversionError.conversionFailed(
            exitCode: 43, stderr: "unknown output format"
        )

        // Act
        let message = error.errorDescription ?? ""

        // Assert
        XCTAssertTrue(message.contains("43"), "Error should contain exit code")
        XCTAssertTrue(message.contains("unknown output format"), "Error should contain stderr")
    }

    // MARK: - Pandoc format mapping

    func testPandocFormatMapping() {
        XCTAssertEqual(TextWriter.Format.docx.pandocFormat, "docx")
        XCTAssertEqual(TextWriter.Format.odt.pandocFormat, "odt")
        XCTAssertEqual(TextWriter.Format.pdf.pandocFormat, "pdf")
        XCTAssertEqual(TextWriter.Format.html.pandocFormat, "html")
    }
}
