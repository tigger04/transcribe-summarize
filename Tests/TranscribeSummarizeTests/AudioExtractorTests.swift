// ABOUTME: Integration tests for AudioExtractor using real sample audio.
// ABOUTME: Tests audio probing, WAV conversion, and error handling.

import XCTest
@testable import TranscribeSummarize

final class AudioExtractorTests: XCTestCase {

    var samplePath: String!

    override func setUpWithError() throws {
        guard let resourceURL = Bundle.module.url(forResource: "sample", withExtension: "mp3") else {
            throw XCTSkip("sample.mp3 not found in test resources")
        }
        samplePath = resourceURL.path
    }

    // MARK: - Probe Tests

    func testProbeReturnsValidAudioInfo() async throws {
        let extractor = AudioExtractor(verbose: 0)
        let info = try await extractor.probe(samplePath)

        // sample.mp3 is ~113 seconds, mono, 48kHz
        XCTAssertGreaterThan(info.duration, 100.0, "Duration should be > 100s")
        XCTAssertLessThan(info.duration, 120.0, "Duration should be < 120s")
        XCTAssertEqual(info.channels, 1, "Should be mono")
        XCTAssertEqual(info.sampleRate, 48000, "Should be 48kHz")
        XCTAssertEqual(info.codec, "mp3", "Should be MP3 codec")
    }

    func testProbeFailsForMissingFile() async throws {
        let extractor = AudioExtractor(verbose: 0)

        do {
            _ = try await extractor.probe("/nonexistent/file.mp3")
            XCTFail("Expected error for missing file")
        } catch {
            // Expected - file doesn't exist
            XCTAssertTrue(error is AudioExtractor.AudioError)
        }
    }

    // MARK: - Extract Tests

    func testExtractCreatesValidWav() async throws {
        let extractor = AudioExtractor(verbose: 0)
        let (wavPath, info) = try await extractor.extract(from: samplePath, minimumDuration: 10.0)

        defer { AudioExtractor.cleanup(wavPath) }

        // Verify WAV file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: wavPath), "WAV file should exist")

        // Verify it's a valid WAV by probing it
        let wavInfo = try await extractor.probe(wavPath)
        XCTAssertEqual(wavInfo.sampleRate, 16000, "WAV should be 16kHz")
        XCTAssertEqual(wavInfo.channels, 1, "WAV should be mono")
        XCTAssertEqual(wavInfo.codec, "pcm_s16le", "WAV should be PCM 16-bit LE")

        // Duration should be preserved
        XCTAssertEqual(wavInfo.duration, info.duration, accuracy: 0.5, "Duration should be preserved")
    }

    func testExtractRejectsTooShortAudio() async throws {
        let extractor = AudioExtractor(verbose: 0)

        do {
            // Request minimum 200 seconds, but sample is only ~113 seconds
            _ = try await extractor.extract(from: samplePath, minimumDuration: 200.0)
            XCTFail("Expected error for too-short audio")
        } catch let error as AudioExtractor.AudioError {
            if case .tooShort(let duration, let minimum) = error {
                XCTAssertGreaterThan(duration, 100.0)
                XCTAssertEqual(minimum, 200.0)
            } else {
                XCTFail("Expected tooShort error, got: \(error)")
            }
        }
    }

    func testExtractFailsForMissingFile() async throws {
        let extractor = AudioExtractor(verbose: 0)

        do {
            _ = try await extractor.extract(from: "/nonexistent/file.mp3")
            XCTFail("Expected error for missing file")
        } catch {
            // Expected - file doesn't exist
            XCTAssertTrue(error is AudioExtractor.AudioError)
        }
    }

    // MARK: - Cleanup Tests

    func testCleanupRemovesFile() async throws {
        let extractor = AudioExtractor(verbose: 0)
        let (wavPath, _) = try await extractor.extract(from: samplePath, minimumDuration: 10.0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: wavPath))

        AudioExtractor.cleanup(wavPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: wavPath))
    }

    func testCleanupHandlesMissingFile() {
        // Should not throw for non-existent file
        AudioExtractor.cleanup("/nonexistent/file.wav")
        // If we get here without crashing, the test passes
    }
}
