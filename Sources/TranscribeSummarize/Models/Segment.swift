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

    /// SRT timestamp with comma-separated milliseconds: HH:MM:SS,mmm
    var srtStartTimestamp: String { formatMillisecondTimestamp(start, separator: ",") }
    var srtEndTimestamp: String { formatMillisecondTimestamp(end, separator: ",") }

    /// VTT timestamp with period-separated milliseconds: HH:MM:SS.mmm
    var vttStartTimestamp: String { formatMillisecondTimestamp(start, separator: ".") }
    var vttEndTimestamp: String { formatMillisecondTimestamp(end, separator: ".") }

    private func formatTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private func formatMillisecondTimestamp(_ seconds: Double, separator: String) -> String {
        let totalMs = Int(seconds * 1000)
        let hours = totalMs / 3_600_000
        let minutes = (totalMs % 3_600_000) / 60_000
        let secs = (totalMs % 60_000) / 1_000
        let ms = totalMs % 1_000
        return String(format: "%02d:%02d:%02d\(separator)%03d", hours, minutes, secs, ms)
    }
}
