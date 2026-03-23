// ABOUTME: Tests for the backupIfExists file backup utility.
// ABOUTME: Verifies .bak creation, timestamped fallback, no-op on absent files, and integration with writers.

import XCTest
@testable import TranscribeSummarize

final class FileUtilitiesTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - RT-031: Existing file is moved to .bak

    /// RT-031: Given a file at the output path, backupIfExists moves it to .bak
    func testBackupCreatesBAKFile_RT031() throws {
        // Arrange
        let filePath = tempDir.appendingPathComponent("meeting.srt").path
        try "original content".write(toFile: filePath, atomically: true, encoding: .utf8)

        // Act
        try backupIfExists(at: filePath)

        // Assert
        let bakPath = filePath + ".bak"
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath),
                        "Original file should be moved away")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakPath),
                       ".bak file should exist")
        let bakContent = try String(contentsOfFile: bakPath, encoding: .utf8)
        XCTAssertEqual(bakContent, "original content",
                        ".bak should contain the original content")
    }

    // MARK: - RT-032: Timestamped .bak when .bak already exists

    /// RT-032: Given both file and .bak exist, backupIfExists creates a timestamped .bak
    func testBackupCreatesTimestampedBAKWhenBAKExists_RT032() throws {
        // Arrange
        let filePath = tempDir.appendingPathComponent("meeting.srt").path
        let bakPath = filePath + ".bak"
        try "first version".write(toFile: bakPath, atomically: true, encoding: .utf8)
        try "second version".write(toFile: filePath, atomically: true, encoding: .utf8)

        // Act
        try backupIfExists(at: filePath)

        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath),
                        "Original file should be moved away")
        // The first .bak should be untouched
        let firstBakContent = try String(contentsOfFile: bakPath, encoding: .utf8)
        XCTAssertEqual(firstBakContent, "first version",
                        "First .bak should be untouched")

        // A timestamped .bak should exist
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let timestampedBaks = files.filter { $0.contains("meeting.srt.") && $0.hasSuffix(".bak") && $0 != "meeting.srt.bak" }
        XCTAssertEqual(timestampedBaks.count, 1,
                        "Exactly one timestamped .bak should exist, found: \(timestampedBaks)")

        let timestampedContent = try String(contentsOfFile: tempDir.appendingPathComponent(timestampedBaks[0]).path, encoding: .utf8)
        XCTAssertEqual(timestampedContent, "second version",
                        "Timestamped .bak should contain the second version")
    }

    // MARK: - RT-033: No-op when file absent

    /// RT-033: Given no file at the path, backupIfExists does nothing and does not error
    func testBackupNoOpWhenFileAbsent_RT033() throws {
        // Arrange
        let filePath = tempDir.appendingPathComponent("nonexistent.srt").path

        // Act — should not throw
        try backupIfExists(at: filePath)

        // Assert
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let bakFiles = files.filter { $0.hasSuffix(".bak") }
        XCTAssertTrue(bakFiles.isEmpty, "No .bak files should be created")
    }

    // MARK: - RT-034: Writer integration — backup happens before write

    /// RT-034: Writing via a writer to an existing file path results in .bak
    func testWriterBacksUpExistingFile_RT034() throws {
        // Arrange
        let filePath = tempDir.appendingPathComponent("output.srt").path
        try "old subtitles".write(toFile: filePath, atomically: true, encoding: .utf8)

        let segments = [
            Segment(start: 1.0, end: 3.0, text: "New content.", speaker: nil, confidence: 0.95),
        ]

        // Act — simulate what commands do: backup then write
        try backupIfExists(at: filePath)
        let writer = SRTWriter()
        try writer.write(segments: segments, to: filePath)

        // Assert
        let bakPath = filePath + ".bak"
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakPath),
                       ".bak should exist with old content")
        let bakContent = try String(contentsOfFile: bakPath, encoding: .utf8)
        XCTAssertEqual(bakContent, "old subtitles")

        let newContent = try String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertTrue(newContent.contains("New content."),
                       "New file should contain the new content")
    }
}
