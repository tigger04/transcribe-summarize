// ABOUTME: Local LLM integration via Ollama.
// ABOUTME: Free alternative using OpenAI-compatible API at localhost.

import Foundation

struct OllamaProvider: LLMProvider {
    private let model: String
    private let verbose: Int
    private let baseURL: String

    init(verbose: Int = 0) throws {
        guard let model = ConfigStore.resolve(configKey: "ollama_model", envKey: "OLLAMA_MODEL") else {
            throw LLMError.missingAPIKey("OLLAMA_MODEL not set (config or env, e.g., mistral, llama3)")
        }
        self.model = model
        self.verbose = verbose
        self.baseURL = ConfigStore.resolve(configKey: "ollama_host", envKey: "OLLAMA_HOST")
            ?? "http://localhost:11434"
    }

    func summarise(transcript: String) async throws -> Summary {
        let prompt = buildSummaryPrompt(transcript: transcript)

        if verbose > 0 {
            print("Generating summary with Ollama (\(model))...")
        }

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": false
        ]

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.requestFailed("Invalid Ollama URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 300  // 5 minutes for local inference

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.requestFailed("Cannot connect to Ollama at \(baseURL). Is it running?")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.requestFailed("Invalid response from Ollama")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed("Ollama HTTP \(httpResponse.statusCode): \(body)")
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> Summary {
        struct OllamaResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
        guard let text = response.choices.first?.message.content else {
            throw LLMError.parseError("Empty response from Ollama")
        }

        return try parseSummaryJSON(text)
    }
}
