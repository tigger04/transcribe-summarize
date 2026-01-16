# ABOUTME: Homebrew formula for transcribe-summarize.
# ABOUTME: Builds from source. Python venv for diarization created on first use.

class TranscribeSummarize < Formula
  desc "Transcribe audio files and generate meeting summaries"
  homepage "https://github.com/tigger04/transcribe-recording"
  url "https://github.com/tigger04/transcribe-recording/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "1143d75596208fbe26e8c11da949080b6fcef3155e9bf839348c520025b60f2e"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on "ffmpeg"
  depends_on "whisper-cpp"
  depends_on "ollama" => :optional

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/transcribe-summarize"
    (share/"transcribe-summarize").install "scripts/diarize.py"
  end

  def caveats
    <<~EOS
      Speaker diarization requires a one-time setup on first use.
      The tool will automatically install Python dependencies when needed.

      To enable diarization:
        1. Create account at https://huggingface.co
        2. Accept model license at https://huggingface.co/pyannote/speaker-diarization-3.1
        3. Generate token at https://huggingface.co/settings/tokens
        4. Set: export HF_TOKEN="your_token"

      For LLM summarization, set one of:
        export ANTHROPIC_API_KEY="your_key"  # Claude (default)
        export OPENAI_API_KEY="your_key"     # OpenAI

      For local LLM via Ollama (install with --with-ollama):
        brew services start ollama
        ollama pull mistral
        export OLLAMA_MODEL="mistral"
    EOS
  end

  test do
    assert_match "transcribe-summarize", shell_output("#{bin}/transcribe-summarize --version")
  end
end
