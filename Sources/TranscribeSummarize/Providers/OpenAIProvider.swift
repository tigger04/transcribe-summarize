// ABOUTME: OpenAI API integration for summarisation.
// ABOUTME: Uses gpt-4o for quality summaries.

import Foundation

struct OpenAIProvider: LLMProvider {
    private let apiKey: String
    private let verbose: Int
    private let model = "gpt-4o"

    init(verbose: Int = 0) throws {
        guard let key = ConfigStore.resolve(configKey: "openai_api_key", envKey: "OPENAI_API_KEY") else {
            throw LLMError.missingAPIKey("OPENAI_API_KEY not set (config or env)")
        }
        self.apiKey = key
        self.verbose = verbose
    }

    func summarise(transcript: String) async throws -> Summary {
        let prompt = buildSummaryPrompt(transcript: transcript)

        if verbose > 0 {
            print("Generating summary with OpenAI...")
        }

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4096
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = response.choices.first?.message.content else {
            throw LLMError.parseError("Empty response")
        }

        return try parseSummaryJSON(text)
    }
}
