# transcribe-summarize

Transcribe audio files and generate structured meeting summaries with speaker identification.

## Features

- Transcribe audio from any media file (m4a, mp4, wav, mp3, opus, webm)
- Speaker diarisation (who spoke when)
- LLM-powered meeting summaries with action items
- Configurable output format with confidence indicators
- Fast processing on Apple Silicon via whisper.cpp

## Installation

### From Source

```bash
git clone https://github.com/tigger04/transcribe-recording.git
cd transcribe-recording
make build
make install
```

### Dependencies

```bash
brew install ffmpeg whisper-cpp
```

Optional (for speaker diarisation):
```bash
brew install python@3.11
pip install pyannote.audio torch
```

## Quick Start

```bash
# Basic usage
transcribe-summarize meeting.m4a

# With options
transcribe-summarize meeting.m4a -o summary.md --model small -v

# Dry run (show what would happen)
transcribe-summarize meeting.m4a --dry-run
```

## Configuration

### CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `-o, --output` | Output path | `<input>.md` |
| `-s, --speakers` | Speaker names (comma-separated or file) | Auto-detect |
| `-t, --timestamps` | Include timestamps | `true` |
| `-c, --confidence` | Minimum confidence threshold | `0.8` |
| `-m, --model` | Whisper model (tiny/base/small/medium/large) | `base` |
| `--llm` | LLM provider (claude/openai/llama) | `claude` |
| `-v` | Verbosity (-v, -vv, -vvv) | quiet |
| `--dry-run` | Show what would be done | - |

### Config File

Create `.transcribe.yaml` in your home directory or project:

```yaml
model: small
confidence: 0.85
llm: claude
speakers:
  - Alice
  - Bob
```

### Environment Variables

```bash
# LLM API keys
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export LLAMA_MODEL_PATH="/path/to/model.gguf"

# Speaker diarisation
export HF_TOKEN="hf_..."
```

## Speaker Diarisation Setup

Speaker identification requires pyannote-audio:

```bash
# Install dependencies
pip install pyannote.audio torch

# Get HuggingFace token
# 1. Create account: https://huggingface.co
# 2. Accept license: https://huggingface.co/pyannote/speaker-diarization-3.1
# 3. Generate token: https://huggingface.co/settings/tokens

export HF_TOKEN="your_token"
```

## Output Format

```markdown
# Meeting Title

**Date:** 2024-01-15
**Duration:** 23:45
**Participants:** Alice, Bob
**Transcription Confidence:** 92% (Good)

## Summary

### Key Points
- Decision 1
- Decision 2

### Actions
| Action | Assigned To | Due Date |
|--------|-------------|----------|
| Task 1 | Alice | Friday |

## Transcript

[00:00:05] **Alice:** Hello everyone...
[00:00:12] **Bob:** Hi, ready to start.
```

## Development

```bash
# Build debug
make build-debug

# Run tests
make test

# Clean
make clean
```

## License

MIT
