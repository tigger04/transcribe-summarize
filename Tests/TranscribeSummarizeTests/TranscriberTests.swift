// ABOUTME: Integration tests for Transcriber using real whisper transcription.
// ABOUTME: Uses tiny model for speed; skips if whisper-cli unavailable.

import XCTest
@testable import TranscribeSummarize

final class TranscriberTests: XCTestCase {

    var samplePath: String!
    var wavPath: String?

    override func setUpWithError() throws {
        // Get sample audio
        guard let resourceURL = Bundle.module.url(forResource: "sample", withExtension: "mp3") else {
            throw XCTSkip("sample.mp3 not found in test resources")
        }
        samplePath = resourceURL.path

        // Check whisper-cli is available
        guard commandExists("whisper-cli") || commandExists("whisper-cpp") else {
            throw XCTSkip("whisper-cli not installed (brew install whisper-cpp)")
        }
    }

    override func tearDownWithError() throws {
        // Clean up any temporary WAV file
        if let path = wavPath {
            AudioExtractor.cleanup(path)
        }
    }

    // MARK: - Helper

    private func commandExists(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Transcription Tests

    func testTranscribeProducesSegments() async throws {
        // First convert to WAV (required by Transcriber)
        let extractor = AudioExtractor(verbose: 0)
        let (path, _) = try await extractor.extract(from: samplePath, minimumDuration: 10.0)
        wavPath = path

        // Use tiny model for speed
        let transcriber = Transcriber(model: .tiny, verbose: 0)
        let segments = try await transcriber.transcribe(wavPath: path)

        // Verify we got segments
        XCTAssertFalse(segments.isEmpty, "Should produce at least one segment")

        // Verify segment structure
        let firstSegment = segments[0]
        XCTAssertGreaterThanOrEqual(firstSegment.start, 0.0, "Start time should be >= 0")
        XCTAssertGreaterThan(firstSegment.end, firstSegment.start, "End should be after start")
        XCTAssertFalse(firstSegment.text.isEmpty, "Text should not be empty")
        XCTAssertGreaterThan(firstSegment.confidence, 0.0, "Confidence should be > 0")
        XCTAssertLessThanOrEqual(firstSegment.confidence, 1.0, "Confidence should be <= 1")

        // Verify segments cover reasonable duration
        let totalDuration = segments.last!.end
        XCTAssertGreaterThan(totalDuration, 60.0, "Should transcribe most of the audio")
    }

    func testTranscribeSegmentsAreOrdered() async throws {
        let extractor = AudioExtractor(verbose: 0)
        let (path, _) = try await extractor.extract(from: samplePath, minimumDuration: 10.0)
        wavPath = path

        let transcriber = Transcriber(model: .tiny, verbose: 0)
        let segments = try await transcriber.transcribe(wavPath: path)

        // Verify segments are in chronological order
        for i in 1..<segments.count {
            XCTAssertGreaterThanOrEqual(
                segments[i].start,
                segments[i-1].start,
                "Segments should be in chronological order"
            )
        }
    }

    func testTranscribeFailsForMissingFile() async throws {
        let transcriber = Transcriber(model: .tiny, verbose: 0)

        do {
            _ = try await transcriber.transcribe(wavPath: "/nonexistent/audio.wav")
            XCTFail("Expected error for missing file")
        } catch {
            // Expected - file doesn't exist
            XCTAssertTrue(error is Transcriber.TranscribeError)
        }
    }

    // MARK: - Model Tests

    func testModelFilenames() {
        XCTAssertEqual(Transcriber.Model.tiny.filename, "ggml-tiny.bin")
        XCTAssertEqual(Transcriber.Model.base.filename, "ggml-base.bin")
        XCTAssertEqual(Transcriber.Model.small.filename, "ggml-small.bin")
        XCTAssertEqual(Transcriber.Model.medium.filename, "ggml-medium.bin")
        XCTAssertEqual(Transcriber.Model.large.filename, "ggml-large.bin")
    }

    func testModelSizes() {
        // Verify approximate sizes are documented
        XCTAssertEqual(Transcriber.Model.tiny.approximateSize, "75MB")
        XCTAssertEqual(Transcriber.Model.base.approximateSize, "142MB")
        XCTAssertEqual(Transcriber.Model.small.approximateSize, "466MB")
        XCTAssertEqual(Transcriber.Model.medium.approximateSize, "1.5GB")
        XCTAssertEqual(Transcriber.Model.large.approximateSize, "2.9GB")
    }
}
