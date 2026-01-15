# Implementation Plan: transcribe-summarize

## Overview

A Swift CLI tool that transcribes audio files and produces structured markdown with speaker diarisation and LLM-generated summaries. Distributable via Homebrew.

**Binary name:** `transcribe-summarize`

## Architecture

```
transcribe-summarize
├── Sources/
│   └── TranscribeSummarize/
│       ├── main.swift                 # Entry point
│       ├── CLI.swift                  # ArgumentParser command
│       ├── Config.swift               # Configuration loading
│       ├── Pipeline/
│       │   ├── AudioExtractor.swift   # ffmpeg wrapper
│       │   ├── Transcriber.swift      # whisper.cpp wrapper
│       │   ├── Diariser.swift         # pyannote-audio wrapper
│       │   └── Summariser.swift       # LLM provider abstraction
│       ├── Providers/
│       │   ├── LLMProvider.swift      # Protocol
│       │   ├── ClaudeProvider.swift
│       │   ├── OpenAIProvider.swift
│       │   └── LlamaProvider.swift
│       ├── Models/
│       │   ├── Transcript.swift       # Data structures
│       │   ├── Segment.swift
│       │   └── Summary.swift
│       └── Output/
│           └── MarkdownWriter.swift   # Output formatting
├── Package.swift
├── .transcribe.yaml.example
└── Formula/
    └── transcribe-summarize.rb        # Homebrew formula
```

## External Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| ffmpeg | Audio extraction/conversion | `brew install ffmpeg` |
| whisper.cpp | Transcription | `brew install whisper-cpp` |
| Python 3.11+ | Diarisation runtime | `brew install python@3.11` |
| pyannote-audio | Speaker diarisation | pip in venv |
| llama.cpp | Local LLM (optional) | `brew install llama.cpp` |

## Swift Dependencies (Package.swift)

- swift-argument-parser (CLI)
- Yams (YAML config parsing)
- swift-http-types + AsyncHTTPClient (API calls)

## Implementation Phases

### Phase 1: Project Scaffold & CLI

1. Create Swift package with executable target
2. Implement CLI with ArgumentParser matching vision spec flags
3. Configuration loading (CLI > YAML > env > defaults)
4. Basic input validation (file exists, supported format)

**Deliverable:** `transcribe-summarize --help` works, validates input file

### Phase 2: Audio Pipeline

1. AudioExtractor: ffmpeg wrapper to extract/convert audio to WAV
2. Duration detection, minimum length check (10s default)
3. Audio quality heuristics (optional: silence ratio, signal level)

**Deliverable:** Extracts audio from any media file to temp WAV

### Phase 3: Transcription

1. Transcriber: whisper.cpp subprocess wrapper
2. Parse whisper.cpp JSON output (timestamps, text, confidence)
3. Model selection (tiny, base, small, medium, large)
4. Progress reporting

**Deliverable:** Produces raw transcript with timestamps

### Phase 4: Diarisation

1. Python helper script using pyannote-audio
2. Diariser: subprocess wrapper calling Python script
3. Merge diarisation segments with transcript segments
4. Speaker labelling (Speaker 1, 2, or provided names)
5. Graceful fallback if diarisation fails

**Deliverable:** Transcript with speaker labels

### Phase 5: LLM Summarisation

1. LLMProvider protocol
2. ClaudeProvider (Anthropic API)
3. OpenAIProvider (OpenAI API)
4. LlamaProvider (llama.cpp subprocess)
5. Prompt engineering for summary structure
6. API key management (env vars, config file)

**Deliverable:** Generates structured summary from transcript

### Phase 6: Output Generation

1. MarkdownWriter assembling final document
2. Metadata extraction (date, duration, participants)
3. Confidence flagging for low-quality segments
4. Timestamp formatting [HH:MM:SS]

**Deliverable:** Complete markdown output per vision spec

### Phase 7: Polish & Error Handling

1. Comprehensive error messages
2. --dry-run implementation
3. Verbose logging levels
4. Cleanup temp files

### Phase 8: Testing

1. Unit tests for each component
2. Integration tests with sample audio
3. End-to-end test with real meeting recording

### Phase 9: Distribution

1. Homebrew formula with dependencies
2. README with installation instructions
3. Release workflow (GitHub releases + formula update)

## Key Design Decisions

### Subprocess vs Native Integration

Using subprocesses for external tools (ffmpeg, whisper.cpp, pyannote, llama.cpp):

- Simpler implementation
- Matches existing CLI tool patterns
- Avoids C/Python binding complexity
- Tools can be upgraded independently

### Diarisation Strategy

pyannote-audio requires Python. Options:

1. **Chosen:** Bundle a Python helper script, call via subprocess
2. Alternative: Require user to run diarisation separately
3. Future: Investigate Swift-native alternatives (CoreML?)

### Configuration Hierarchy

```
1. CLI flags (highest priority)
2. .transcribe.yaml in current directory
3. ~/.transcribe.yaml
4. Environment variables (TRANSCRIBE_*)
5. Compiled defaults
```

## Files to Create

1. `Package.swift` - Swift package manifest
2. `Sources/TranscribeSummarize/*.swift` - All source files
3. `scripts/diarize.py` - Python diarisation helper
4. `Tests/TranscribeSummarizeTests/*.swift` - Test files
5. `Formula/transcribe-summarize.rb` - Homebrew formula
6. `README.md` - Installation and usage
7. `.transcribe.yaml.example` - Example config
8. `Makefile` - Build/test/install targets

## Verification

1. `swift build` compiles without errors
2. `swift test` passes all tests
3. `./transcribe-summarize --help` shows all flags from vision spec
4. `./transcribe-summarize sample.m4a` produces valid markdown output
5. Homebrew formula installs cleanly: `brew install --build-from-source ./Formula/transcribe-summarize.rb`

## Resolved Decisions

1. **Whisper models:** Download on first run. Tool checks for model, downloads if missing.
2. **HuggingFace token:** Diarisation is optional. Skip with warning if no token configured.
3. **Binary name:** `transcribe-summarize`

## Risk Considerations

- pyannote-audio setup can be finicky (Python venv, CUDA/MPS)
- Whisper model download requires ~150MB+ network transfer
- Claude API costs scale with transcript length
