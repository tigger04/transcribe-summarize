// ABOUTME: Data model for structured meeting summary.
// ABOUTME: Maps to the markdown output format from vision spec.

import Foundation

struct Summary {
    var title: String
    var date: String?
    var duration: String
    var participants: [String]
    var confidenceRating: String

    var agenda: String?
    var keyPoints: KeyPoints
    var themesAndTone: String
    var actions: [Action]
    var conclusion: String

    struct KeyPoints {
        var decisions: [String]
        var discussions: [String]
        var unresolvedQuestions: [String]
    }

    struct Action {
        let description: String
        let assignedTo: String?
        let dueDate: String?
    }
}
