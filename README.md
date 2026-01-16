# transcribe-summarize

Transcribe audio files and generate structured meeting summaries with speaker identification.

## Quickstart

```bash
brew install tigger04/tap/transcribe-summarize
```

Basic usage:

```bash
transcribe-summarize meeting.m4a
```

### Optional: Speaker Diarization

To identify who said what, set a HuggingFace token:

1. Create account: https://huggingface.co
2. Accept license: https://huggingface.co/pyannote/speaker-diarization-3.1
3. Generate token: https://huggingface.co/settings/tokens
4. `export HF_TOKEN="your_token"`

On first use with HF_TOKEN set, the tool will automatically set up the Python
environment for diarization (one-time, ~800MB download).

### LLM Configuration

Ollama and the mistral model are installed automatically. For local summarization (no API key needed):

```bash
brew services start ollama
export OLLAMA_MODEL="mistral"
transcribe-summarize --llm ollama meeting.m4a
```

Or use cloud providers:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."  # Claude (default)
export OPENAI_API_KEY="sk-..."         # OpenAI
```

## Features

- Transcribe audio from any media file (m4a, mp4, wav, mp3, opus, webm)
- Speaker diarization (who spoke when)
- LLM-powered meeting summaries with action items
- Configurable output format with confidence indicators
- Fast processing on Apple Silicon via whisper.cpp

## Installation from Source

### Prerequisites

```bash
brew install ffmpeg whisper-cpp ollama
ollama pull mistral
```

### Build and Install

```bash
git clone https://github.com/tigger04/transcribe-recording.git
cd transcribe-recording
make install
```

The Python environment for speaker diarization is created automatically on first use.

## Usage

```bash
# Basic usage
transcribe-summarize meeting.m4a

# With options
transcribe-summarize meeting.m4a -o summary.md --model small -v

# Dry run (show what would happen)
transcribe-summarize meeting.m4a --dry-run
```

### CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `-o, --output` | Output path | `<input>.md` |
| `-s, --speakers` | Speaker names (comma-separated or file) | Auto-detect |
| `-t, --timestamps` | Include timestamps | `true` |
| `-c, --confidence` | Minimum confidence threshold | `0.8` |
| `-m, --model` | Whisper model (tiny/base/small/medium/large) | `base` |
| `--llm` | LLM provider (claude/openai/ollama) | `claude` |
| `-v` | Verbosity (-v, -vv, -vvv) | quiet |
| `--dry-run` | Show what would be done | - |

### Config File

Create `~/.config/transcribe-summarize/config.yaml` or `.transcribe.yaml` in your project:

```yaml
model: small
confidence: 0.85
llm: ollama
speakers:
  - Alice
  - Bob

# API keys (optional, can also use environment variables)
ollama_model: mistral
anthropic_api_key: sk-ant-...
openai_api_key: sk-...
hf_token: hf_...
```

Config priority: local `.transcribe.yaml` > `~/.config/transcribe-summarize/config.yaml` > legacy `~/.transcribe.yaml`

API keys can be set in config file or environment variables; config takes precedence.

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
