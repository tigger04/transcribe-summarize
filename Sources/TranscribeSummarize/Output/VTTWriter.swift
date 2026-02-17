// ABOUTME: Generates WebVTT subtitle files from transcript segments.
// ABOUTME: Supports optional speaker labels via WebVTT voice spans.

import Foundation

struct VTTWriter {

    /// Generate WebVTT-formatted string from segments.
    func generate(segments: [Segment]) -> String {
        var output = "WEBVTT\n\n"

        for segment in segments {
            // Timestamp line: HH:MM:SS.mmm --> HH:MM:SS.mmm
            output += "\(segment.vttStartTimestamp) --> \(segment.vttEndTimestamp)\n"

            // Text line with optional voice span per WebVTT spec
            if let speaker = segment.speaker {
                output += "<v \(speaker)>\(segment.text)</v>\n"
            } else {
                output += "\(segment.text)\n"
            }

            // Blank line between cues
            output += "\n"
        }

        return output
    }

    /// Write WebVTT output to a file.
    func write(segments: [Segment], to outputPath: String) throws {
        let content = generate(segments: segments)
        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}
