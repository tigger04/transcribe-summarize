// ABOUTME: File utility functions for output management.
// ABOUTME: Provides backup-before-overwrite to prevent accidental data loss.

import Foundation

/// If a file exists at `path`, move it to a backup before new content is written.
///
/// - First attempt: `<path>.bak`
/// - If `.bak` already exists: `<path>.<ISO8601-timestamp>.bak`
///
/// Does nothing if no file exists at the path.
func backupIfExists(at path: String) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return }

    let bakPath = path + ".bak"

    if !fm.fileExists(atPath: bakPath) {
        try fm.moveItem(atPath: path, toPath: bakPath)
        fputs("Backed up existing file to \(bakPath)\n", stderr)
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: Date())
        let timestampedPath = "\(path).\(timestamp).bak"
        try fm.moveItem(atPath: path, toPath: timestampedPath)
        fputs("Backed up existing file to \(timestampedPath)\n", stderr)
    }
}
