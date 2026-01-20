#!/usr/bin/env python3
# ABOUTME: Speaker diarization helper supporting pyannote-audio and speechbrain backends.
# ABOUTME: Outputs JSON with speaker segments for Swift to consume.

"""
Speaker diarization with automatic backend selection.

Usage: python3 diarize.py <audio_file> [--backend auto|pyannote|speechbrain]

Backends:
  pyannote    - Best quality (~10-15% DER), requires HuggingFace token
  speechbrain - Good quality (~15-20% DER), no token required (Apache 2.0)
  auto        - Use pyannote if HF_TOKEN set, otherwise speechbrain (default)

Output: JSON to stdout with speaker segments:
[
  {"start": 0.0, "end": 5.2, "speaker": "SPEAKER_00"},
  {"start": 5.2, "end": 12.1, "speaker": "SPEAKER_01"},
  ...
]

For pyannote, you must accept ALL THREE model licenses:
  https://huggingface.co/pyannote/speaker-diarization-3.1
  https://huggingface.co/pyannote/segmentation-3.0
  https://huggingface.co/pyannote/speaker-diarization-community-1
"""

import argparse
import json
import os
import sys
import warnings

warnings.filterwarnings("ignore")

# Patch for torchaudio 2.9+ which removed list_audio_backends
# Must be done early before any audio library imports
import torchaudio
if not hasattr(torchaudio, 'list_audio_backends'):
    torchaudio.list_audio_backends = lambda: []

# Set environment for PyTorch 2.6+ compatibility with older models
# This allows loading models pickled with older PyTorch versions
os.environ.setdefault("TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD", "1")

# Patch huggingface_hub for speechbrain compatibility
# speechbrain 1.0.3 uses deprecated use_auth_token parameter
from functools import wraps
import huggingface_hub

_original_download = huggingface_hub.hf_hub_download


@wraps(_original_download)
def _patched_download(*args, **kwargs):
    if 'use_auth_token' in kwargs:
        kwargs['token'] = kwargs.pop('use_auth_token')
    return _original_download(*args, **kwargs)


huggingface_hub.hf_hub_download = _patched_download

_original_snapshot = huggingface_hub.snapshot_download


@wraps(_original_snapshot)
def _patched_snapshot(*args, **kwargs):
    if 'use_auth_token' in kwargs:
        kwargs['token'] = kwargs.pop('use_auth_token')
    return _original_snapshot(*args, **kwargs)


huggingface_hub.snapshot_download = _patched_snapshot


def diarize_pyannote(audio_file, token):
    """Diarize using pyannote-audio (requires HuggingFace token)."""
    try:
        from pyannote.audio import Pipeline
    except ImportError:
        return {"error": "pyannote.audio not installed", "help": "Run: pip install pyannote.audio"}

    pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1",
        token=token
    )

    result = pipeline(audio_file)

    # pyannote.audio 4.x returns DiarizeOutput, need to access .speaker_diarization
    # pyannote.audio 3.x returns Annotation directly
    if hasattr(result, 'speaker_diarization'):
        diarization = result.speaker_diarization
    else:
        diarization = result

    segments = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        segments.append({
            "start": round(turn.start, 3),
            "end": round(turn.end, 3),
            "speaker": speaker
        })

    return segments


def diarize_speechbrain(audio_file, num_speakers=None):
    """Diarize using speechbrain (no token required, Apache 2.0 license).

    Uses ECAPA-TDNN embeddings + spectral clustering for speaker identification.
    """
    import torch
    import numpy as np
    from sklearn.cluster import SpectralClustering, AgglomerativeClustering
    from huggingface_hub import hf_hub_download
    from speechbrain.lobes.models.ECAPA_TDNN import ECAPA_TDNN
    from speechbrain.lobes.features import Fbank

    # Download and load the ECAPA-TDNN model directly (avoids custom.py issue)
    embedding_path = hf_hub_download('speechbrain/spkrec-ecapa-voxceleb', 'embedding_model.ckpt')

    model = ECAPA_TDNN(
        input_size=80,
        channels=[1024, 1024, 1024, 1024, 3072],
        kernel_sizes=[5, 3, 3, 3, 1],
        dilations=[1, 2, 3, 4, 1],
        attention_channels=128,
        lin_neurons=192
    )

    checkpoint = torch.load(embedding_path, map_location='cpu', weights_only=False)
    model.load_state_dict(checkpoint)
    model.eval()

    # Feature extractor (mel filterbanks)
    compute_features = Fbank(n_mels=80)

    # Load audio
    waveform, sample_rate = torchaudio.load(audio_file)

    # Resample to 16kHz if needed (model expects 16kHz)
    if sample_rate != 16000:
        resampler = torchaudio.transforms.Resample(sample_rate, 16000)
        waveform = resampler(waveform)
        sample_rate = 16000

    # Convert to mono if stereo
    if waveform.shape[0] > 1:
        waveform = torch.mean(waveform, dim=0, keepdim=True)

    # Segment the audio into windows for embedding extraction
    window_size = 1.5  # seconds
    hop_size = 0.75    # seconds (50% overlap)
    window_samples = int(window_size * sample_rate)
    hop_samples = int(hop_size * sample_rate)

    total_samples = waveform.shape[1]

    # Extract embeddings for each window
    embeddings = []
    timestamps = []

    for start_sample in range(0, total_samples - window_samples + 1, hop_samples):
        end_sample = start_sample + window_samples
        segment = waveform[:, start_sample:end_sample]

        # Get embedding: audio -> mel features -> ECAPA-TDNN -> embedding
        with torch.no_grad():
            # Compute mel filterbank features
            feats = compute_features(segment)
            # Run through ECAPA-TDNN model
            embedding = model(feats)
            embeddings.append(embedding.squeeze().numpy())

        start_time = start_sample / sample_rate
        end_time = end_sample / sample_rate
        timestamps.append((start_time, end_time))

    if not embeddings:
        return []

    embeddings = np.array(embeddings)

    # Estimate number of speakers if not provided
    if num_speakers is None:
        # Use eigenvalue analysis to estimate number of speakers
        # Default to 2 if estimation fails
        num_speakers = estimate_num_speakers(embeddings, max_speakers=8)

    # Cluster embeddings
    if num_speakers == 1:
        labels = np.zeros(len(embeddings), dtype=int)
    else:
        try:
            clustering = SpectralClustering(
                n_clusters=num_speakers,
                affinity='cosine',
                random_state=42
            )
            labels = clustering.fit_predict(embeddings)
        except Exception:
            # Fallback to agglomerative clustering
            clustering = AgglomerativeClustering(
                n_clusters=num_speakers,
                metric='cosine',
                linkage='average'
            )
            labels = clustering.fit_predict(embeddings)

    # Merge adjacent segments with same speaker
    segments = merge_segments(timestamps, labels)

    return segments


def estimate_num_speakers(embeddings, max_speakers=8):
    """Estimate number of speakers using eigenvalue analysis."""
    from sklearn.metrics.pairwise import cosine_similarity
    import numpy as np

    if len(embeddings) < 2:
        return 1

    # Compute affinity matrix
    similarity = cosine_similarity(embeddings)

    # Compute eigenvalues
    try:
        eigenvalues = np.linalg.eigvalsh(similarity)
        eigenvalues = np.sort(eigenvalues)[::-1]

        # Find elbow point (biggest gap in eigenvalues)
        max_speakers = min(max_speakers, len(eigenvalues) - 1)
        gaps = []
        for i in range(1, max_speakers):
            if eigenvalues[i] > 0:
                gap = eigenvalues[i-1] / eigenvalues[i]
                gaps.append(gap)
            else:
                gaps.append(float('inf'))

        if gaps:
            num_speakers = np.argmax(gaps) + 1
            num_speakers = max(2, min(num_speakers, max_speakers))
        else:
            num_speakers = 2
    except Exception:
        num_speakers = 2

    return num_speakers


def merge_segments(timestamps, labels):
    """Merge adjacent segments with the same speaker label."""
    if not timestamps:
        return []

    segments = []
    current_speaker = labels[0]
    current_start = timestamps[0][0]
    current_end = timestamps[0][1]

    for i in range(1, len(timestamps)):
        if labels[i] == current_speaker:
            # Extend current segment
            current_end = timestamps[i][1]
        else:
            # Save current segment and start new one
            segments.append({
                "start": round(current_start, 3),
                "end": round(current_end, 3),
                "speaker": f"SPEAKER_{current_speaker:02d}"
            })
            current_speaker = labels[i]
            current_start = timestamps[i][0]
            current_end = timestamps[i][1]

    # Don't forget the last segment
    segments.append({
        "start": round(current_start, 3),
        "end": round(current_end, 3),
        "speaker": f"SPEAKER_{current_speaker:02d}"
    })

    return segments


def main():
    parser = argparse.ArgumentParser(
        description="Speaker diarization with automatic backend selection"
    )
    parser.add_argument("audio_file", help="Path to audio file")
    parser.add_argument(
        "--backend",
        choices=["auto", "pyannote", "speechbrain"],
        default="auto",
        help="Diarization backend (default: auto)"
    )
    parser.add_argument(
        "--token",
        help="HuggingFace token for pyannote (or set HF_TOKEN env var)"
    )
    parser.add_argument(
        "--num-speakers",
        type=int,
        help="Number of speakers (optional, auto-detected if not specified)"
    )
    args = parser.parse_args()

    if not os.path.exists(args.audio_file):
        print(json.dumps({"error": f"File not found: {args.audio_file}"}))
        sys.exit(1)

    token = args.token or os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")

    # Determine which backend to use
    backend = args.backend
    if backend == "auto":
        backend = "pyannote" if token else "speechbrain"

    try:
        if backend == "pyannote":
            if not token:
                print(json.dumps({
                    "error": "HuggingFace token required for pyannote backend",
                    "help": "Set HF_TOKEN env var or use --backend speechbrain"
                }))
                sys.exit(1)
            segments = diarize_pyannote(args.audio_file, token)
        else:
            segments = diarize_speechbrain(args.audio_file, args.num_speakers)

        # Check for error dict
        if isinstance(segments, dict) and "error" in segments:
            print(json.dumps(segments))
            sys.exit(1)

        print(json.dumps(segments))

    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
