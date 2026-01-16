#!/usr/bin/env python3
# ABOUTME: Speaker diarization helper using pyannote-audio.
# ABOUTME: Outputs JSON with speaker segments for Swift to consume.

"""
Speaker diarization using pyannote-audio.

Usage: python3 diarize.py <audio_file> [--token <hf_token>]

Output: JSON to stdout with speaker segments:
[
  {"start": 0.0, "end": 5.2, "speaker": "SPEAKER_00"},
  {"start": 5.2, "end": 12.1, "speaker": "SPEAKER_01"},
  ...
]

Requires:
  pip install pyannote.audio torch

HuggingFace token required - get one at:
  https://huggingface.co/settings/tokens

You must also accept the model license at:
  https://huggingface.co/pyannote/speaker-diarization-3.1
"""

import argparse
import json
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="Speaker diarization with pyannote-audio")
    parser.add_argument("audio_file", help="Path to audio file")
    parser.add_argument("--token", help="HuggingFace token (or set HF_TOKEN env var)")
    args = parser.parse_args()

    token = args.token or os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")

    if not token:
        print(json.dumps({
            "error": "HuggingFace token required",
            "help": "Get a token at https://huggingface.co/settings/tokens and set HF_TOKEN env var"
        }))
        sys.exit(1)

    if not os.path.exists(args.audio_file):
        print(json.dumps({"error": f"File not found: {args.audio_file}"}))
        sys.exit(1)

    try:
        from pyannote.audio import Pipeline
    except ImportError:
        print(json.dumps({
            "error": "pyannote.audio not installed",
            "help": "Run: pip install pyannote.audio torch"
        }))
        sys.exit(1)

    try:
        pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            use_auth_token=token
        )

        diarization = pipeline(args.audio_file)

        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append({
                "start": round(turn.start, 3),
                "end": round(turn.end, 3),
                "speaker": speaker
            })

        print(json.dumps(segments))

    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
