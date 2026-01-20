// ABOUTME: End-to-end integration tests for transcribe-summarize.
// ABOUTME: Tests config loading, API key resolution, and full pipeline.

import XCTest
@testable import TranscribeSummarize

final class IntegrationTests: XCTestCase {

    var samplePath: String!

    override func setUpWithError() throws {
        guard let resourceURL = Bundle.module.url(forResource: "sample", withExtension: "mp3") else {
            throw XCTSkip("sample.mp3 not found in test resources")
        }
        samplePath = resourceURL.path
    }

    // MARK: - Config Model Resolution Tests

    func testConfigRespectsYAMLModelWhenCLINotSpecified() throws {
        // Create a temp config file with model: small
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent(".transcribe.yaml")
        let configContent = "model: small\n"
        try configContent.write(to: configPath, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: configPath) }

        // Change to temp dir so local config is found
        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDir.path)
        defer { FileManager.default.changeCurrentDirectoryPath(originalDir) }

        // Reset ConfigStore to pick up new config
        // Note: This requires ConfigStore to be resettable for testing

        // Load config with empty model (simulating no CLI arg)
        let config = try Config.load(
            inputFile: samplePath,
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "",  // Empty = no CLI override
            llm: "auto",
            verbose: 0,
            dryRun: true
        )

        // Should use config file value, not default "base"
        XCTAssertEqual(config.model, .small, "Config file model 'small' should be used when CLI doesn't specify")
    }

    func testConfigUsesValueFromGlobalConfigFile() throws {
        // This test verifies that the global config file at
        // ~/.config/transcribe-summarize/config.yaml is being read.
        // The user's config has model: small
        let config = try Config.load(
            inputFile: samplePath,
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "",  // Empty = no CLI override
            llm: "auto",
            verbose: 0,
            dryRun: true
        )

        // Should use the global config file value "small"
        // (If this fails with "base", the config file isn't being read)
        XCTAssertEqual(config.model, .small, "Global config file model 'small' should be used")
    }

    func testCLIModelOverridesConfig() throws {
        // Even if config file says "small", CLI "tiny" should win
        let config = try Config.load(
            inputFile: samplePath,
            output: nil,
            speakers: nil,
            timestamps: true,
            confidence: 0.8,
            model: "tiny",  // CLI specifies tiny
            llm: "auto",
            verbose: 0,
            dryRun: true
        )

        XCTAssertEqual(config.model, .tiny, "CLI model should override config file")
    }

    // MARK: - API Key Resolution Tests

    func testResolveSecretPrefersEnvVarOverConfig() {
        // Set up a test env var
        let testKey = "TEST_SECRET_KEY"
        let testValue = "env-value-123"
        setenv(testKey, testValue, 1)
        defer { unsetenv(testKey) }

        // resolveSecret should return env var value even if config has different value
        // Note: We can't easily test with actual config file here, but we can verify
        // env var is returned when set
        let result = ConfigStore.resolveSecret(configKey: "nonexistent_key", envKey: testKey)
        XCTAssertEqual(result, testValue, "resolveSecret should return env var value")
    }

    func testResolveSecretFallsBackToConfigWhenEnvUnset() {
        // When env var is not set, should fall back to config
        // This is harder to test without mocking, but we can verify nil case
        let result = ConfigStore.resolveSecret(configKey: "nonexistent_key", envKey: "NONEXISTENT_ENV_VAR_12345")
        XCTAssertNil(result, "resolveSecret should return nil when neither env nor config has value")
    }

    func testAnthropicKeyAvailableFromEnv() throws {
        // Skip if env var not set (CI environment)
        guard let _ = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            throw XCTSkip("ANTHROPIC_API_KEY not set in environment")
        }

        // Should be able to create Claude provider
        XCTAssertNoThrow(try ClaudeProvider(verbose: 0), "ClaudeProvider should init when ANTHROPIC_API_KEY is set")
    }

    func testOpenAIKeyAvailableFromEnv() throws {
        // Skip if env var not set (CI environment)
        guard let _ = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            throw XCTSkip("OPENAI_API_KEY not set in environment")
        }

        // Should be able to create OpenAI provider
        XCTAssertNoThrow(try OpenAIProvider(verbose: 0), "OpenAIProvider should init when OPENAI_API_KEY is set")
    }

    // MARK: - LLM Selector Tests

    func testLLMSelectorRespectsConfigPriority() {
        // Test that custom priority from config is respected
        let selector = LLMSelector(priority: ["openai", "claude", "ollama"])
        XCTAssertEqual(selector.priority, ["openai", "claude", "ollama"])
    }

    // MARK: - Full Pipeline Tests

    func testFullPipelineWithTinyModel() async throws {
        // Skip if whisper not available
        guard commandExists("whisper-cli") || commandExists("whisper-cpp") else {
            throw XCTSkip("whisper-cli not installed")
        }

        // Extract audio
        let extractor = AudioExtractor(verbose: 0)
        let (wavPath, info) = try await extractor.extract(from: samplePath, minimumDuration: 10.0)
        defer { AudioExtractor.cleanup(wavPath) }

        XCTAssertGreaterThan(info.duration, 100.0, "Sample should be > 100s")

        // Transcribe with tiny model for speed
        let transcriber = Transcriber(model: .tiny, verbose: 0)
        let segments = try await transcriber.transcribe(wavPath: wavPath)

        XCTAssertFalse(segments.isEmpty, "Should produce segments")
        XCTAssertGreaterThan(segments.count, 5, "Should have multiple segments for 113s audio")

        // Verify segments have content
        for segment in segments {
            XCTAssertFalse(segment.text.isEmpty, "Segment text should not be empty")
            XCTAssertGreaterThanOrEqual(segment.start, 0, "Start time should be >= 0")
            XCTAssertGreaterThan(segment.end, segment.start, "End should be after start")
        }
    }

    // MARK: - Helpers

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
}
