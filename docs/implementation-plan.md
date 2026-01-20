# Implementation Plan: transcribe-summarize

## Overview

A Swift CLI tool that transcribes audio files and produces structured markdown with speaker diarization and LLM-generated summaries. Distributable via Homebrew.

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
│       │   ├── Diarizer.swift         # pyannote-audio wrapper
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
| Python 3.11+ | Diarization runtime | `brew install python@3.11` |
| pyannote-audio | Speaker diarization | pip in venv |
| Ollama | Local LLM | `brew install ollama` |

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
3. Audio quality analysis and automatic preprocessing (implemented)
   - Analyzes mean/max volume, RMS level, noise floor, crest factor
   - Auto-applies: amplification, denoising, normalization, dynamic compression
   - Controlled via `--preprocess auto|none|analyze` flag

**Deliverable:** Extracts audio from any media file to temp WAV with optional preprocessing

### Phase 3: Transcription

1. Transcriber: whisper.cpp subprocess wrapper
2. Parse whisper.cpp JSON output (timestamps, text, confidence)
3. Model selection (tiny, base, small, medium, large)
4. Progress reporting

**Deliverable:** Produces raw transcript with timestamps

### Phase 4: Diarization

1. Python helper script using pyannote-audio
2. Diarizer: subprocess wrapper calling Python script
3. Merge diarization segments with transcript segments
4. Speaker labelling (Speaker 1, 2, or provided names)
5. Graceful fallback if diarization fails

**Deliverable:** Transcript with speaker labels

### Phase 5: LLM Summarization

1. LLMProvider protocol
2. ClaudeProvider (Anthropic API)
3. OpenAIProvider (OpenAI API)
4. OllamaProvider (Ollama HTTP API)
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

Using subprocesses for external tools (ffmpeg, whisper.cpp, pyannote) and HTTP APIs (Claude, OpenAI, Ollama):

- Simpler implementation
- Matches existing CLI tool patterns
- Avoids C/Python binding complexity
- Tools can be upgraded independently

### Diarization Strategy

pyannote-audio requires Python. Options:

1. **Chosen:** Bundle a Python helper script, call via subprocess
2. Alternative: Require user to run diarization separately
3. Future: Investigate Swift-native alternatives (CoreML?)

### Configuration Hierarchy

```
1. CLI flags (highest priority)
2. .transcribe.yaml in current directory
3. ~/.config/transcribe-summarize/config.yaml
4. ~/.transcribe.yaml (legacy, for backwards compatibility)
5. Environment variables (TRANSCRIBE_*)
6. Compiled defaults
```

### LLM Provider Auto-Selection

When `--llm auto` (the default), the tool automatically selects an LLM provider based on availability:

**Priority order:** ollama > claude > openai (local-first, free before paid)

A provider is "available" if its credentials are configured:
- **ollama:** `OLLAMA_MODEL` env var or `ollama_model` in config
- **claude:** `ANTHROPIC_API_KEY` env var or `anthropic_api_key` in config
- **openai:** `OPENAI_API_KEY` env var or `openai_api_key` in config

The `LLMSelector` struct in `Config.swift` handles this logic.

## Files to Create

1. `Package.swift` - Swift package manifest
2. `Sources/TranscribeSummarize/*.swift` - All source files
3. `scripts/diarize.py` - Python diarization helper
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
2. **HuggingFace token:** Diarization is optional. Signpost user where to get token. Skip with warning if no token configured.
3. **Binary name:** `transcribe-summarize`

## Risk Considerations

- pyannote-audio setup can be finicky (Python venv, CUDA/MPS)
- Whisper model download requires ~150MB+ network transfer
- Claude and OpenAI API costs scale with transcript length - warn user for longer transcripts, suggest local llama3.1:8b model as free alternative

## Release Process

Use `make release V=x.y.z` to:
1. Run all tests
2. Update version in `main.swift`
3. Commit and tag
4. Push to GitHub
5. Update formula with new SHA256

The formula must then be copied to the Homebrew tap repository.
