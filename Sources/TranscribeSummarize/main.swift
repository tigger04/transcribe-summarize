// ABOUTME: Root command for the transcribe CLI with subcommand dispatch.
// ABOUTME: Handles backward compatibility for deprecated transcribe-summarize invocation.

import ArgumentParser
import Foundation

@main
struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe audio and video files.",
        discussion: """
            Subcommands:
              summarize  - Full pipeline: transcribe, diarize, LLM summary → markdown
              srt        - Generate SRT subtitles
              vtt        - Generate WebVTT subtitles
              words      - Generate word-by-word JSON with timestamps

            Config file: ~/.config/transcribe-summarize/config.yaml

            All subcommands support --speakers for speaker diarization.
            """,
        version: "0.2.19",
        subcommands: [SummarizeCommand.self, SRTCommand.self, VTTCommand.self, WordsCommand.self]
    )

    /// Override the default entry point to handle backward compatibility.
    /// When invoked as `transcribe-summarize`, auto-inject the `summarize` subcommand
    /// and print a deprecation warning.
    static func main() async {
        let invocationName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

        if invocationName == "transcribe-summarize" {
            fputs("Warning: 'transcribe-summarize' is deprecated. Use 'transcribe summarize' instead.\n", stderr)

            var args = Array(CommandLine.arguments.dropFirst())

            // Only inject "summarize" if user didn't already specify a known subcommand
            let knownSubcommands: Set<String> = ["summarize", "srt", "vtt", "words", "help"]
            if args.isEmpty || !knownSubcommands.contains(args[0]) {
                args.insert("summarize", at: 0)
            }

            do {
                var command = try parseAsRoot(args)
                if var asyncCmd = command as? AsyncParsableCommand {
                    try await asyncCmd.run()
                } else {
                    try command.run()
                }
            } catch {
                exit(withError: error)
            }
        } else {
            do {
                var command = try parseAsRoot()
                if var asyncCmd = command as? AsyncParsableCommand {
                    try await asyncCmd.run()
                } else {
                    try command.run()
                }
            } catch {
                exit(withError: error)
            }
        }
    }
}
