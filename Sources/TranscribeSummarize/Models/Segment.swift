// ABOUTME: Data model for a single transcript segment.
// ABOUTME: Contains timestamp, text, speaker label, and confidence score.

import Foundation

struct Segment: Codable {
    let start: Double
    let end: Double
    let text: String
    var speaker: String?
    let confidence: Double

    var startTimestamp: String {
        formatTimestamp(start)
    }

    var endTimestamp: String {
        formatTimestamp(end)
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
