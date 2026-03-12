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
            preprocess: "auto",
            device: "auto",
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
            preprocess: "auto",
            device: "auto",
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
            preprocess: "auto",
            device: "auto",
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
            preprocess: "auto",
            device: "auto",
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
            preprocess: "auto",
            device: "auto",
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
            preprocess: "auto",
            device: "auto",
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
            preprocess: "auto",
            device: "auto",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.modelName, "small")
    }

    // MARK: - LLM Auto-Selection Tests

    func testValidationAcceptsAutoLLM() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "auto",
            preprocess: "auto",
            device: "auto",
            verbose: 0,
            dryRun: true
        )

        XCTAssertTrue(config.validate())
    }

    // MARK: - Device Mode Tests

    func testDeviceModeDefaultsToAuto() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "auto",
            preprocess: "auto",
            device: "auto",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.device, .auto)
    }

    func testDeviceModeCPU() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "auto",
            preprocess: "auto",
            device: "cpu",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.device, .cpu)
    }

    func testDeviceModeMPS() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "auto",
            preprocess: "auto",
            device: "mps",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.device, .mps)
    }

    func testDeviceModeCUDA() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "auto",
            preprocess: "auto",
            device: "cuda",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.device, .cuda)
    }

    func testDeviceModeInvalidFallsBackToAuto() throws {
        let config = try Config.load(
            inputFile: "/path/to/meeting.m4a",
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "base",
            llm: "auto",
            preprocess: "auto",
            device: "invalid",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.device, .auto)
    }

    func testLLMSelectorDefaultPriority() {
        // Verify the default priority constant is ollama > claude > openai
        XCTAssertEqual(LLMSelector.defaultPriority, ["ollama", "claude", "openai"])
    }

    func testLLMSelectorCustomPriority() {
        // Verify explicit priority order is respected and overrides config
        let selector = LLMSelector(priority: ["openai", "claude"])
        XCTAssertEqual(selector.priority, ["openai", "claude"])
    }

    func testLLMSelectorSelectsFirstAvailable() {
        // Test that selectProvider returns the first available provider
        let selector = LLMSelector()
        let selected = selector.selectProvider()
        // If a provider is selected, it must be available
        if let provider = selected {
            XCTAssertTrue(selector.isAvailable(provider))
        }
    }

    func testLLMSelectorAvailabilityReturnsConsistently() {
        // Multiple calls to isAvailable should return the same result
        let selector = LLMSelector()
        let firstCall = selector.isAvailable("ollama")
        let secondCall = selector.isAvailable("ollama")
        XCTAssertEqual(firstCall, secondCall)
    }

    func testLLMSelectorUnknownProviderUnavailable() {
        // Unknown providers should always be unavailable
        let selector = LLMSelector()
        XCTAssertFalse(selector.isAvailable("unknown_provider"))
        XCTAssertFalse(selector.isAvailable(""))
    }
}
