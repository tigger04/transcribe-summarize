// ABOUTME: Converts markdown files to other document formats via pandoc.
// ABOUTME: Pandoc is optional — only required when a pandoc-backed format is requested.

import Foundation

enum PandocConverter {

    enum ConversionError: LocalizedError {
        case pandocNotFound(format: String)
        case conversionFailed(exitCode: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .pandocNotFound(let format):
                var msg = "Error: pandoc is required for .\(format) output. Install with: brew install pandoc"
                if format == "pdf" {
                    msg += "\nNote: PDF output also requires a LaTeX engine (e.g. brew install --cask basictex)"
                }
                return msg
            case .conversionFailed(let exitCode, let stderr):
                return "Error: pandoc conversion failed (exit \(exitCode)): \(stderr)"
            }
        }
    }

    /// Check whether pandoc is available on PATH.
    static func isAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["pandoc", "--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Convert a markdown file to the specified format using pandoc.
    /// Throws if pandoc is not installed or the conversion fails.
    static func convert(from markdownPath: String, to outputPath: String, format: TextWriter.Format) throws {
        guard isAvailable() else {
            throw ConversionError.pandocNotFound(format: format.rawValue)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["pandoc", "-f", "markdown", "-t", format.pandocFormat, "-o", outputPath, markdownPath]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw ConversionError.conversionFailed(exitCode: process.terminationStatus, stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
