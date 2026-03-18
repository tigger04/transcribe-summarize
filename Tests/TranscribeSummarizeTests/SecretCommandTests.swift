// ABOUTME: Tests for command-based secret resolution (issues #28, #31).
// ABOUTME: Verifies priority, command diagnostics, and failure warnings.

import XCTest
@testable import TranscribeSummarize

final class SecretCommandTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        ConfigStore._resetForTesting()
    }

    // MARK: - Command Resolution Priority Tests

    func testResolveSecretCommandReturnsValueFromCommand() {
        // Arrange: config has a command that echoes a secret
        ConfigStore._setTestConfig([
            "anthropic_api_key_command": "echo test-secret-value"
        ])

        // Act: resolve with no env var set
        let result = ConfigStore.resolveSecret(
            configKey: "anthropic_api_key",
            envKey: "NONEXISTENT_ENV_VAR_CMD_TEST_1"
        )

        // Assert: command output is returned
        XCTAssertEqual(result, "test-secret-value",
                       "resolveSecret should run command and return its stdout")
    }

    func testResolveSecretEnvVarOverridesCommand() {
        // Arrange: both env var and command are available
        let envKey = "TEST_SECRET_CMD_ENV_OVERRIDE"
        setenv(envKey, "env-wins", 1)
        defer { unsetenv(envKey) }

        ConfigStore._setTestConfig([
            "test_key_command": "echo command-value"
        ])

        // Act
        let result = ConfigStore.resolveSecret(configKey: "test_key", envKey: envKey)

        // Assert: env var takes precedence
        XCTAssertEqual(result, "env-wins",
                       "Environment variable should override command")
    }

    func testResolveSecretCommandOverridesPlainValue() {
        // Arrange: both command and plain value in config
        ConfigStore._setTestConfig([
            "api_key": "plain-value",
            "api_key_command": "echo command-value"
        ])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "api_key",
            envKey: "NONEXISTENT_ENV_VAR_CMD_TEST_2"
        )

        // Assert: command wins over plain value
        XCTAssertEqual(result, "command-value",
                       "Command should override plain config value")
    }

    func testResolveSecretCommandFailureFallsToPlainValue() {
        // Arrange: command fails, plain value exists
        ConfigStore._setTestConfig([
            "api_key": "fallback-value",
            "api_key_command": "/usr/bin/false"
        ])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "api_key",
            envKey: "NONEXISTENT_ENV_VAR_CMD_TEST_3"
        )

        // Assert: falls through to plain value
        XCTAssertEqual(result, "fallback-value",
                       "Failed command should fall through to plain config value")
    }

    func testResolveSecretNoCommandFallsToPlainValue() {
        // Arrange: no command key, just plain value
        ConfigStore._setTestConfig([
            "api_key": "plain-only"
        ])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "api_key",
            envKey: "NONEXISTENT_ENV_VAR_CMD_TEST_4"
        )

        // Assert: plain value is used
        XCTAssertEqual(result, "plain-only",
                       "Without command, plain config value should be used")
    }

    func testResolveSecretCommandTrimsWhitespace() {
        // Arrange: command output has trailing newline (common for echo)
        ConfigStore._setTestConfig([
            "api_key_command": "printf '  secret-with-spaces  \\n'"
        ])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "api_key",
            envKey: "NONEXISTENT_ENV_VAR_CMD_TEST_5"
        )

        // Assert: whitespace is trimmed
        XCTAssertEqual(result, "secret-with-spaces",
                       "Command output should be trimmed of whitespace")
    }

    func testResolveSecretCommandEmptyOutputFallsToPlainValue() {
        // Arrange: command succeeds but produces no output
        ConfigStore._setTestConfig([
            "api_key": "fallback-for-empty",
            "api_key_command": "printf ''"
        ])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "api_key",
            envKey: "NONEXISTENT_ENV_VAR_CMD_TEST_6"
        )

        // Assert: empty command output falls through to plain value
        XCTAssertEqual(result, "fallback-for-empty",
                       "Empty command output should fall through to plain config value")
    }

    // MARK: - Multi-Env-Key Secret Resolution Tests

    func testResolveSecretWithMultipleEnvKeysFirstWins() {
        // Arrange
        let envKey1 = "TEST_MULTI_KEY_1"
        let envKey2 = "TEST_MULTI_KEY_2"
        setenv(envKey1, "first-env", 1)
        setenv(envKey2, "second-env", 1)
        defer {
            unsetenv(envKey1)
            unsetenv(envKey2)
        }

        ConfigStore._setTestConfig([:])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "test_token",
            envKeys: [envKey1, envKey2]
        )

        // Assert: first matching env var wins
        XCTAssertEqual(result, "first-env",
                       "First matching env var should win")
    }

    func testResolveSecretWithMultipleEnvKeysFallsToCommand() {
        // Arrange: no env vars set, command available
        ConfigStore._setTestConfig([
            "test_token_command": "echo cmd-secret"
        ])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "test_token",
            envKeys: ["NONEXISTENT_MULTI_1", "NONEXISTENT_MULTI_2"]
        )

        // Assert: command is used when no env vars match
        XCTAssertEqual(result, "cmd-secret",
                       "Command should be used when no env vars match")
    }

    func testResolveSecretWithMultipleEnvKeysFallsToPlainValue() {
        // Arrange: no env vars, no command, plain value exists
        ConfigStore._setTestConfig([
            "test_token": "plain-token"
        ])

        // Act
        let result = ConfigStore.resolveSecret(
            configKey: "test_token",
            envKeys: ["NONEXISTENT_MULTI_3", "NONEXISTENT_MULTI_4"]
        )

        // Assert: plain value is used as last resort
        XCTAssertEqual(result, "plain-token",
                       "Plain config value should be used as last resort")
    }

    // MARK: - Command Diagnostic Tests (Issue #31)

    /// RT-008: Failing command reports diagnostic with key name and exit status
    func testCheckConfigCommandFailureReportsDiagnostic_RT008() {
        // Arrange
        ConfigStore._setTestConfig([
            "api_key_command": "/usr/bin/false"
        ])

        // Act
        let status = ConfigStore.checkConfigCommand(for: "api_key")

        // Assert
        if case .failed(let key, let exitCode) = status {
            XCTAssertEqual(key, "api_key_command")
            XCTAssertNotEqual(exitCode, 0)
        } else {
            XCTFail("Expected .failed status for non-zero exit, got \(status)")
        }
    }

    /// RT-009: Absent command key returns .notConfigured with no diagnostic
    func testCheckConfigCommandAbsentReturnsNotConfigured_RT009() {
        // Arrange
        ConfigStore._setTestConfig([
            "api_key": "plain-value"
        ])

        // Act
        let status = ConfigStore.checkConfigCommand(for: "api_key")

        // Assert
        if case .notConfigured = status {
            // Expected — no warning should be emitted for absent keys
        } else {
            XCTFail("Expected .notConfigured for absent command key, got \(status)")
        }
    }

    /// RT-010: LLMSelector error message references _command config keys
    func testLLMSelectorErrorMessageReferencesCommandKeys_RT010() {
        // Arrange: no providers available
        ConfigStore._setTestConfig([:])

        // Act
        let selector = LLMSelector()
        let message = selector.unavailableMessage()

        // Assert
        XCTAssertTrue(message.contains("_command"),
                      "Error message should reference _command config keys")
        XCTAssertTrue(message.contains("anthropic_api_key_command"),
                      "Error message should mention anthropic_api_key_command")
        XCTAssertTrue(message.contains("openai_api_key_command"),
                      "Error message should mention openai_api_key_command")
    }

    func testCheckConfigCommandEmptyOutputReportsDiagnostic() {
        // Arrange
        ConfigStore._setTestConfig([
            "api_key_command": "printf ''"
        ])

        // Act
        let status = ConfigStore.checkConfigCommand(for: "api_key")

        // Assert
        if case .emptyOutput(let key) = status {
            XCTAssertEqual(key, "api_key_command")
        } else {
            XCTFail("Expected .emptyOutput for empty command output, got \(status)")
        }
    }

    func testCheckConfigCommandSuccessReturnsResolved() {
        // Arrange
        ConfigStore._setTestConfig([
            "api_key_command": "echo test-value"
        ])

        // Act
        let status = ConfigStore.checkConfigCommand(for: "api_key")

        // Assert
        if case .resolved = status {
            // Expected
        } else {
            XCTFail("Expected .resolved for successful command, got \(status)")
        }
    }
}
