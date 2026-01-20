// ABOUTME: Anthropic Claude API integration for summarisation.
// ABOUTME: Uses Claude Sonnet 4 for cost-effective quality.

import Foundation

struct ClaudeProvider: LLMProvider {
    private let apiKey: String
    private let verbose: Int
    private let model = "claude-sonnet-4-20250514"

    init(verbose: Int = 0) throws {
        guard let key = ConfigStore.resolveSecret(configKey: "anthropic_api_key", envKey: "ANTHROPIC_API_KEY") else {
            throw LLMError.missingAPIKey("ANTHROPIC_API_KEY not set (env or config)")
        }
        self.apiKey = key
        self.verbose = verbose
    }

    func summarise(transcript: String) async throws -> Summary {
        let prompt = buildSummaryPrompt(transcript: transcript)

        if verbose > 0 {
            print("Generating summary with Claude...")
        }

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.requestFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> Summary {
        struct ClaudeResponse: Codable {
            struct Content: Codable {
                let text: String
            }
            let content: [Content]
        }

        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = response.content.first?.text else {
            throw LLMError.parseError("Empty response")
        }

        return try parseSummaryJSON(text)
    }
}
