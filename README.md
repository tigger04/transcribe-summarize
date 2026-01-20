# Transcribe-Summarize

Turn meeting recordings into structured documents with transcripts, speaker labels, and summaries—all locally.

**What it does:** You give it an audio file from a meeting, interview, or conversation. It gives you back a readable document with:
- A summary of key points and action items
- A full transcript with timestamps
- Speaker attribution (identifying who said what)

**How it works:** Everything runs locally on your Mac - your audio never leaves your computer.* The tool uses AI to transcribe speech (via whisper.cpp), identify different speakers (via speechbrain), and summarize the conversation (via Ollama).

**No accounts needed:** Works out of the box without any API keys or signups. Just install and run.

<sub>* If you optionally configure Claude or OpenAI API keys for summarization, your transcript text (not audio) will be sent to those services.</sub>

*macOS only — requires Apple Silicon or Intel Mac.*

# Rationale
Dozens of commercial apps offer meeting transcription and summarization, all built on open-source technology. This project makes that capability freely available, with no accounts or subscriptions required.

# Practical Usage
Open QuickTime Player, select File -> New Audio Recording, record your meeting, then run the file through this tool.

# Etiquette
Consider informing participants that you're using transcription software. I've yet to have an objection, though I'd honour one.

# Accessibility
This is currently a command-line tool. I know that can intimidate some users. I'd welcome collaboration from a developer with UI experience to create a graphical interface. Open an issue on GitHub if interested, I'd love to hear from you!

## Quickstart

```bash
brew install tigger04/tap/transcribe-summarize
```

Basic usage:

```bash
transcribe-summarize meeting.m4a
```

That's it! Everything works out of the box. Optionally, you can add API keys for higher quality results (see below).

### Improving Quality (Optional)

For better results, you can configure:

| Feature | Default (free, local) | Optional upgrade |
|---------|----------------------|------------------|
| **Summarization** | Ollama (llama3.1:8b) | Claude or OpenAI API |
| **Speaker diarization** | speechbrain (~15-20% error) | pyannote (~10-15% error) with HF_TOKEN |

### Speaker Diarization

Speaker identification works automatically using speechbrain (Apache 2.0 license, no account needed).

For slightly better accuracy, you can optionally use pyannote:

1. Create account: https://huggingface.co
2. Accept **all three** model licenses (click "Agree and access repository" on each):
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
   - https://huggingface.co/pyannote/speaker-diarization-community-1
3. Generate token: https://huggingface.co/settings/tokens
4. `export HF_TOKEN="your_token"`

On first use, the tool automatically sets up the Python environment for diarization (one-time, ~1GB download).

### LLM Configuration

By default, transcribe-summarize uses **auto-selection** to choose an LLM provider based on what's configured:

**Priority order:** ollama > claude > openai (local-first, free before paid)

Ollama and llama3.1:8b are installed automatically with Homebrew. For local summarization (no API key needed):

```bash
brew services start ollama
export OLLAMA_MODEL="llama3.1:8b"
transcribe-summarize meeting.m4a
```

Or use cloud providers:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."  # Claude
export OPENAI_API_KEY="sk-..."         # OpenAI
```

To explicitly choose a provider:

```bash
transcribe-summarize --llm claude meeting.m4a   # Force Claude
transcribe-summarize --llm ollama meeting.m4a   # Force Ollama
```

#### Alternative Local Models

For resource-constrained systems, lighter models are available:

| Model | Parameters | RAM | Best For |
|-------|-----------|-----|----------|
| `llama3.1:8b` | 8B | 8GB | High-quality summaries (default) |
| `llama3.2:3b` | 3B | 4-6GB | Resource-constrained systems |
| `phi3:mini` | 3.8B | 4GB | Analytical/reasoning tasks |

```bash
ollama pull llama3.2:3b
export OLLAMA_MODEL="llama3.2:3b"
```

## Features

- Transcribe audio from any media file (m4a, mp4, wav, mp3, opus, webm)
- Speaker diarization (who spoke when)
- LLM-powered meeting summaries with action items
- Configurable output format with confidence indicators
- Fast processing on Apple Silicon via whisper.cpp

## Installation from Source (macOS)

### Prerequisites

```bash
brew install ffmpeg whisper-cpp ollama
ollama pull llama3.1:8b
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
| `--llm` | LLM provider (claude/openai/ollama/auto) | `auto` |
| `--preprocess` | Audio preprocessing (auto/none/analyze) | `auto` |
| `-v` | Verbosity (-v, -vv, -vvv) | quiet |
| `--dry-run` | Show what would be done | - |

### Config File

Create `~/.config/transcribe-summarize/config.yaml` or `.transcribe.yaml` in your project:

```yaml
model: small
llm: auto
preprocess: auto              # auto, none, or analyze
ollama_model: llama3.1:8b
anthropic_api_key: sk-ant-...  # Overridden by ANTHROPIC_API_KEY env var
openai_api_key: sk-...         # Overridden by OPENAI_API_KEY env var
hf_token: hf_...               # Overridden by HF_TOKEN env var
# llm_priority:                # Custom auto-selection order (default shown)
#   - ollama
#   - claude
#   - openai
# speakers:
#   - Alice
#   - Bob
```

Config priority: local `.transcribe.yaml` > `~/.config/transcribe-summarize/config.yaml` > legacy `~/.transcribe.yaml`

**How speaker naming works:** Names are assigned in order of first appearance in the audio. The first person to speak gets the first name, second speaker gets the second name, etc.

Tips for correct speaker assignment:
1. Listen to the first few seconds to know who speaks first
2. Or run once without names, check the transcript to identify speakers, then re-run with correctly ordered names
3. Or just edit the markdown output to swap names if needed

**Security note:** Environment variables take precedence over config file for API keys. Prefer env vars to avoid storing secrets in files.

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

### Releasing

To publish a new version:

```bash
make release V=x.y.z
```

This will:
1. Run all tests
2. Update the version in `main.swift`
3. Commit and tag the release
4. Push to GitHub
5. Update the Homebrew formula with the new SHA256

After release, update your Homebrew tap with the new formula.

## License

MIT
