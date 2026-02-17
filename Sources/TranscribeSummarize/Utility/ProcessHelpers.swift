// ABOUTME: Shared utility for checking external command availability.
// ABOUTME: Used by AudioExtractor, Transcriber, Diarizer, and CLI commands.

import Foundation

/// Check whether an external command is available on the system PATH.
func commandExists(_ command: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [command]
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
