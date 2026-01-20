# Vision: Audio Transcription and Meeting Summary Tool

## Purpose

A CLI script that transcribes audio from any media file and produces a structured markdown document containing an intelligent summary and full transcript with speaker identification.

## Input Handling

- Accept any media file containing audio (m4a, mp4, wav, mp3, opus, webm, etc.)
- Configurable output path/naming convention (default: same directory, same basename with .md extension)
- Minimum audio length threshold (default: 10 seconds) to avoid processing trivial clips
- Graceful failure with clear error messages for:
  - Unsupported formats
  - Corrupted/unreadable files
  - Poor audio quality (with confidence threshold)

## Speaker Identification (Diarization)

- Identify and label different speakers in the transcript
- Default to "Speaker 1", "Speaker 2", etc.
- Optional: provide known speaker names via CLI flag or config file to map to identified voices
- If diarization fails: proceed with unlabelled transcript and warn user

## Output Structure

Single markdown file with the following structure:

```
# [Meeting Title or Filename]

**Date:** [from metadata or spoken, if detected]  
**Duration:** [total runtime]  
**Participants:** [list if identifiable]  
**Transcription Confidence:** [overall percentage or rating]

## Summary

### Agenda
[If articulated in the meeting]

### Key Points
- Decisions made
- Significant discussion items
- Questions raised but not resolved

### Themes and Tone
[Brief characterization of the meeting's nature]

### Actions
| Action | Assigned To | Due Date (if stated) |
|--------|-------------|----------------------|
| ...    | ...         | ...                  |

### Conclusion
[How the meeting ended, any agreed next steps]

## Transcript

[HH:MM:SS] **Speaker 1:** Lorem ipsum...  
[HH:MM:SS] **Speaker 2:** Dolor sit amet...  

[Confidence: low] [HH:MM:SS] **Speaker 1:** [inaudible] ...amet consectetur...
```

## Confidence Indicators

- Overall transcription confidence rating in metadata
- Per-segment confidence flags for low-quality sections
- Threshold configuration: below X% confidence, flag segment (default: 80%)
- Option to include/exclude low-confidence segments

## Configuration

Priority order (highest to lowest):
1. CLI flags
2. Config file (.transcribe.yaml in current directory or home)
3. Environment variables
4. Sensible defaults

### CLI Flags (minimum)
```
--output, -o       Output path (default: input basename + .md)
--speakers, -s     Path to speaker names file or comma-separated list
--timestamps, -t   Include timestamps (default: true)
--confidence, -c   Minimum confidence threshold (default: 0.8)
--model, -m        Whisper model size (default: base)
--verbose, -v      Logging verbosity
--dry-run          Show what would be done without processing
```

## Dependencies

- Transcription: whisper.cpp (preferred for Apple Silicon) or openai-whisper
- Diarization: pyannote-audio or equivalent
- Audio processing: ffmpeg
- LLM for summarization: Claude API or local model

## Roadmap (not for v1)

- Real-time transcription
- GUI interface
- Multi-file batch processing (though should be trivially scriptable)
- Translation (transcribe in source language only)

## Success Criteria

- Processes a 1-hour meeting recording in under 10 minutes on M-series Mac
- Produces accurate, readable summary without manual editing for clear audio
- Fails fast and informatively for problematic inputs
