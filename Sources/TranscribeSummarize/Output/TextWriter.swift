// ABOUTME: Formats transcript segments as plain text or markdown.
// ABOUTME: Supports optional timestamps and speaker labels.

import Foundation

struct TextWriter {

    /// Output formats supported by the text subcommand and pandoc pipeline.
    enum Format: String, CaseIterable {
        case txt
        case md
        case docx
        case odt
        case pdf
        case html

        /// Whether this format requires pandoc for conversion.
        var requiresPandoc: Bool {
            switch self {
            case .txt, .md: return false
            case .docx, .odt, .pdf, .html: return true
            }
        }

        /// The pandoc output format name.
        var pandocFormat: String {
            switch self {
            case .docx: return "docx"
            case .odt: return "odt"
            case .pdf: return "pdf"
            case .html: return "html"
            case .txt, .md: return rawValue
            }
        }
    }

    let format: Format
    let includeTimestamps: Bool

    init(format: Format = .txt, includeTimestamps: Bool = false) {
        self.format = format
        self.includeTimestamps = includeTimestamps
    }

    /// Generate formatted text from segments.
    func generate(segments: [Segment]) -> String {
        guard !segments.isEmpty else { return "" }

        switch format {
        case .md:
            return generateMarkdown(segments: segments)
        default:
            return generatePlainText(segments: segments)
        }
    }

    /// Write formatted output to a file.
    func write(segments: [Segment], to outputPath: String) throws {
        let content = generate(segments: segments)
        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    /// Deduce output format from a file path extension.
    /// Returns nil for unrecognised extensions.
    static func deduceFormat(from path: String) -> Format? {
        let ext = (path as NSString).pathExtension.lowercased()
        return Format(rawValue: ext)
    }

    // MARK: - Private

    private func generatePlainText(segments: [Segment]) -> String {
        var lines: [String] = []

        for segment in segments {
            var line = ""

            if includeTimestamps {
                line += "[\(segment.startTimestamp)] "
            }

            if let speaker = segment.speaker {
                line += "\(speaker): "
            }

            line += segment.text
            lines.append(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func generateMarkdown(segments: [Segment]) -> String {
        var paragraphs: [String] = []

        for segment in segments {
            var line = ""

            if includeTimestamps {
                line += "[\(segment.startTimestamp)] "
            }

            if let speaker = segment.speaker {
                line += "**\(speaker):** "
            }

            line += segment.text
            paragraphs.append(line)
        }

        return paragraphs.joined(separator: "\n\n") + "\n"
    }
}
