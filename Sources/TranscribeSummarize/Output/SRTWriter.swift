// ABOUTME: Generates SRT subtitle files from transcript segments.
// ABOUTME: Supports optional speaker labels in [Speaker]: format.

import Foundation

struct SRTWriter {

    /// Generate SRT-formatted string from segments.
    func generate(segments: [Segment]) -> String {
        guard !segments.isEmpty else { return "" }

        var output = ""
        for (index, segment) in segments.enumerated() {
            // Sequence number (1-based)
            output += "\(index + 1)\n"

            // Timestamp line: HH:MM:SS,mmm --> HH:MM:SS,mmm
            output += "\(segment.srtStartTimestamp) --> \(segment.srtEndTimestamp)\n"

            // Text line with optional speaker label
            if let speaker = segment.speaker {
                output += "[\(speaker)]: \(segment.text)\n"
            } else {
                output += "\(segment.text)\n"
            }

            // Blank line between cues
            output += "\n"
        }

        return output
    }

    /// Write SRT output to a file.
    func write(segments: [Segment], to outputPath: String) throws {
        let content = generate(segments: segments)
        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}
