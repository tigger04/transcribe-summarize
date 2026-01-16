# ABOUTME: Homebrew formula for transcribe-summarize.
# ABOUTME: Builds from source, creates managed Python venv for diarisation.

class TranscribeSummarize < Formula
  desc "Transcribe audio files and generate meeting summaries"
  homepage "https://github.com/tigger04/transcribe-recording"
  url "https://github.com/tigger04/transcribe-recording/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "1143d75596208fbe26e8c11da949080b6fcef3155e9bf839348c520025b60f2e"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on "ffmpeg"
  depends_on "whisper-cpp"
  depends_on "python@3.10" => :build

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/transcribe-summarize"
    (share/"transcribe-summarize").install "scripts/diarize.py"

    # Create managed venv for diarisation
    venv = share/"transcribe-summarize/venv"
    system "python3", "-m", "venv", venv
    system venv/"bin/pip", "install", "--upgrade", "pip"
    system venv/"bin/pip", "install", "pyannote.audio", "torch"
  end

  def caveats
    <<~EOS
      Speaker diarisation is ready to use. To enable it:

        1. Create account at https://huggingface.co
        2. Accept model license at https://huggingface.co/pyannote/speaker-diarization-3.1
        3. Generate token at https://huggingface.co/settings/tokens
        4. Set: export HF_TOKEN="your_token"

      For LLM summarisation, set one of:
        export ANTHROPIC_API_KEY="your_key"  # Claude (default)
        export OPENAI_API_KEY="your_key"     # OpenAI
        export LLAMA_MODEL_PATH="/path/to/model.gguf"  # Local
    EOS
  end

  test do
    assert_match "transcribe-summarize", shell_output("#{bin}/transcribe-summarize --version")
  end
end
