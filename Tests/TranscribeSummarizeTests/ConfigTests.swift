// ABOUTME: Unit tests for configuration loading and validation.
// ABOUTME: Tests CLI > YAML > env > defaults priority.

import XCTest
@testable import TranscribeSummarize

final class ConfigTests: XCTestCase {

    func testDefaultOutputPath() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "claude",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.outputPath, "/path/to/meeting.md")
    }

    func testCustomOutputPath() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: "/custom/output.md",
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "claude",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.outputPath, "/custom/output.md")
    }

    func testSpeakerParsing() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: "Alice,Bob,Charlie",
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "claude",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.speakers, ["Alice", "Bob", "Charlie"])
    }

    func testValidationRejectsUnsupportedFormat() throws {
        let config = try Config.load(
            inputFile: "/path/to/document.pdf",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "claude",
            verbose: 0,
            dryRun: true
        )

        XCTAssertFalse(config.validate())
    }

    func testValidationRejectsInvalidConfidence() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 1.5,
            model: "base",
            llm: "claude",
            verbose: 0,
            dryRun: true
        )

        XCTAssertFalse(config.validate())
    }

    func testValidationRejectsInvalidLLM() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "invalid",
            verbose: 0,
            dryRun: true
        )

        XCTAssertFalse(config.validate())
    }

    func testModelParsing() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "small",
            llm: "claude",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.model, .small)
    }
}
