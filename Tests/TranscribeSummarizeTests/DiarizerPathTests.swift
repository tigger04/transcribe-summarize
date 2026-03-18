// ABOUTME: Tests for diarization script path resolution.
// ABOUTME: Verifies that findDiariseScript searches ~/.local/share and Homebrew paths.

import XCTest
@testable import TranscribeSummarize

final class DiarizerPathTests: XCTestCase {

    // MARK: - RT-027: ~/.local/share path is in candidate list

    /// RT-027: make install path is searched for diarize.py
    func testCandidatesIncludeLocalSharePath_RT027() {
        // Arrange
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = "\(home)/.local/share/transcribe-summarize/diarize.py"

        // Assert
        XCTAssertTrue(
            Diarizer.diariseScriptCandidates.contains(expected),
            "Candidates should include ~/.local/share path: \(expected)"
        )
    }

    // MARK: - RT-028: Homebrew paths are in candidate list

    /// RT-028: Homebrew ARM and Intel paths are searched for diarize.py
    func testCandidatesIncludeHomebrewPaths_RT028() {
        // Assert
        XCTAssertTrue(
            Diarizer.diariseScriptCandidates.contains("/opt/homebrew/share/transcribe-summarize/diarize.py"),
            "Candidates should include ARM Homebrew path"
        )
        XCTAssertTrue(
            Diarizer.diariseScriptCandidates.contains("/usr/local/share/transcribe-summarize/diarize.py"),
            "Candidates should include Intel Homebrew path"
        )
    }

    /// RT-027 supplement: ~/.local/share path has higher priority than Homebrew
    func testLocalSharePathPrecedesHomebrew_RT027() {
        // Arrange
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let localPath = "\(home)/.local/share/transcribe-summarize/diarize.py"
        let brewARM = "/opt/homebrew/share/transcribe-summarize/diarize.py"

        let candidates = Diarizer.diariseScriptCandidates
        guard let localIdx = candidates.firstIndex(of: localPath),
              let brewIdx = candidates.firstIndex(of: brewARM) else {
            XCTFail("Both paths should be in candidates")
            return
        }

        // Assert: make install path comes before Homebrew
        XCTAssertLessThan(localIdx, brewIdx,
                          "~/.local/share path should be searched before Homebrew path")
    }
}
