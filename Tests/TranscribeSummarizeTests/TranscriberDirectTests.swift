// ABOUTME: Integration tests for Transcriber.transcribeDirect() output modes.
// ABOUTME: Tests SRT, VTT, and JSON-full native whisper-cli output generation.

import XCTest
@testable import TranscribeSummarize

final class TranscriberDirectTests: XCTestCase {

    var samplePath: String!
    var wavPath: String?

    override func setUpWithError() throws {
        guard let resourceURL = Bundle.module.url(forResource: "sample", withExtension: "mp3") else {
            throw XCTSkip("sample.mp3 not found in test resources")
        }
        samplePath = resourceURL.path

        guard commandExists("whisper-cli") || commandExists("whisper-cpp") else {
            throw XCTSkip("whisper-cli not installed (brew install whisper-cpp)")
        }
    }

    override func tearDownWithError() throws {
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

    private func extractWav() async throws -> String {
        let extractor = AudioExtractor(verbose: 0)
        let (path, _, _) = try await extractor.extract(from: samplePath, minimumDuration: 10.0, preprocess: .none)
        wavPath = path
        return path
    }

    // MARK: - transcribeDirect Tests

    func testTranscribeDirectSRT() async throws {
        let path = try await extractWav()
        let transcriber = Transcriber(model: .tiny, verbose: 0)

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: tempBase + ".srt") }

        let outputPath = try await transcriber.transcribeDirect(
            wavPath: path,
            format: .srt,
            outputBase: tempBase
        )

        XCTAssertTrue(outputPath.hasSuffix(".srt"), "Output should have .srt extension")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath), "SRT file should exist")

        let content = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(content.contains("-->"), "SRT should contain timestamp arrows")
        XCTAssertFalse(content.isEmpty, "SRT should not be empty")
    }

    func testTranscribeDirectVTT() async throws {
        let path = try await extractWav()
        let transcriber = Transcriber(model: .tiny, verbose: 0)

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: tempBase + ".vtt") }

        let outputPath = try await transcriber.transcribeDirect(
            wavPath: path,
            format: .vtt,
            outputBase: tempBase
        )

        XCTAssertTrue(outputPath.hasSuffix(".vtt"), "Output should have .vtt extension")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath), "VTT file should exist")

        let content = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(content.contains("WEBVTT"), "VTT should contain WEBVTT header")
        XCTAssertTrue(content.contains("-->"), "VTT should contain timestamp arrows")
    }

    func testTranscribeDirectJSONFull() async throws {
        let path = try await extractWav()
        let transcriber = Transcriber(model: .tiny, verbose: 0)

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: tempBase + ".json") }

        let outputPath = try await transcriber.transcribeDirect(
            wavPath: path,
            format: .jsonFull,
            outputBase: tempBase
        )

        XCTAssertTrue(outputPath.hasSuffix(".json"), "Output should have .json extension")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath), "JSON file should exist")

        let content = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertFalse(content.isEmpty, "JSON should not be empty")

        // Verify it's valid JSON
        let data = content.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "Output should be valid JSON")
    }

    // MARK: - OutputFormat Tests

    func testOutputFormatExtensions() {
        XCTAssertEqual(Transcriber.OutputFormat.srt.fileExtension, ".srt")
        XCTAssertEqual(Transcriber.OutputFormat.vtt.fileExtension, ".vtt")
        XCTAssertEqual(Transcriber.OutputFormat.jsonFull.fileExtension, ".json")
    }
}
