// ABOUTME: Protocol defining the interface for LLM providers.
// ABOUTME: Implementations: Claude, OpenAI, Ollama.

import Foundation

protocol LLMProvider {
    func summarise(transcript: String) async throws -> Summary
}

enum LLMProviderType: String, CaseIterable {
    case claude
    case openai
    case ollama

    func createProvider(verbose: Int) throws -> LLMProvider {
        switch self {
        case .claude:
            return try ClaudeProvider(verbose: verbose)
        case .openai:
            return try OpenAIProvider(verbose: verbose)
        case .ollama:
            return try OllamaProvider(verbose: verbose)
        }
    }
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(String)
    case requestFailed(String)
    case parseError(String)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "\(provider) API key not configured"
        case .requestFailed(let msg):
            return "LLM request failed: \(msg)"
        case .parseError(let msg):
            return "Failed to parse LLM response: \(msg)"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        }
    }
}

func buildSummaryPrompt(transcript: String) -> String {
    """
    Analyze this meeting transcript and provide a structured summary.

    Return your response as JSON with this exact structure:
    {
      "title": "Brief meeting title",
      "agenda": "Agenda if stated, or null",
      "keyPoints": {
        "decisions": ["Decision 1", "Decision 2"],
        "discussions": ["Topic 1", "Topic 2"],
        "unresolvedQuestions": ["Question 1"]
      },
      "themesAndTone": "Brief characterization of the meeting's nature",
      "actions": [
        {"description": "Action item", "assignedTo": "Person or null", "dueDate": "Date or null"}
      ],
      "conclusion": "How the meeting ended, next steps"
    }

    TRANSCRIPT:
    \(transcript)
    """
}

func parseSummaryJSON(_ jsonString: String) throws -> Summary {
    let cleaned = extractJSON(from: jsonString)
    guard let jsonData = cleaned.data(using: .utf8) else {
        throw LLMError.parseError("Invalid JSON encoding")
    }

    struct SummaryResponse: Codable {
        let title: String
        let agenda: String?
        let keyPoints: KeyPointsResponse
        let themesAndTone: String
        let actions: [ActionResponse]
        let conclusion: String

        struct KeyPointsResponse: Codable {
            let decisions: [String]
            let discussions: [String]
            let unresolvedQuestions: [String]
        }

        struct ActionResponse: Codable {
            let description: String
            let assignedTo: String?
            let dueDate: String?
        }
    }

    let parsed = try JSONDecoder().decode(SummaryResponse.self, from: jsonData)

    return Summary(
        title: parsed.title,
        date: nil,
        duration: "",
        participants: [],
        confidenceRating: "",
        agenda: parsed.agenda,
        keyPoints: Summary.KeyPoints(
            decisions: parsed.keyPoints.decisions,
            discussions: parsed.keyPoints.discussions,
            unresolvedQuestions: parsed.keyPoints.unresolvedQuestions
        ),
        themesAndTone: parsed.themesAndTone,
        actions: parsed.actions.map {
            Summary.Action(description: $0.description, assignedTo: $0.assignedTo, dueDate: $0.dueDate)
        },
        conclusion: parsed.conclusion
    )
}

private func extractJSON(from text: String) -> String {
    if let start = text.range(of: "```json"),
       let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let start = text.range(of: "{"),
       let end = text.range(of: "}", options: .backwards) {
        return String(text[start.lowerBound...end.lowerBound])
    }
    return text
}
