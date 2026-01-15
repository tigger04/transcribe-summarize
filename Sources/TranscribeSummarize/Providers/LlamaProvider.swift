// ABOUTME: Local LLM integration via llama.cpp.
// ABOUTME: Free alternative - no API costs.

import Foundation

struct LlamaProvider: LLMProvider {
    private let verbose: Int
    private let modelPath: String?

    init(verbose: Int = 0) {
        self.verbose = verbose
        self.modelPath = ProcessInfo.processInfo.environment["LLAMA_MODEL_PATH"]
    }

    func summarise(transcript: String) async throws -> Summary {
        guard commandExists("llama-cli") else {
            throw LLMError.modelNotFound("llama-cli not found. Install: brew install llama.cpp")
        }

        guard let modelPath = modelPath, FileManager.default.fileExists(atPath: modelPath) else {
            throw LLMError.modelNotFound("Set LLAMA_MODEL_PATH to your .gguf model file")
        }

        if verbose > 0 {
            print("Generating summary with local LLM (this may take a while)...")
        }

        let prompt = buildSummaryPrompt(transcript: transcript)

        let tempPromptFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try prompt.write(to: tempPromptFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempPromptFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "llama-cli",
            "-m", modelPath,
            "-f", tempPromptFile.path,
            "-n", "2048",
            "--temp", "0.7"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LLMError.requestFailed("llama-cli failed with exit code \(process.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw LLMError.parseError("Could not read llama output")
        }

        return try parseSummaryJSON(output)
    }

    private func commandExists(_ command: String) -> Bool {
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
}
