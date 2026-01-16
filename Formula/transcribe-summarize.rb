# ABOUTME: Homebrew formula for transcribe-summarize.
# ABOUTME: Builds from source. Python venv for diarization created on first use.

class TranscribeSummarize < Formula
  desc "Transcribe audio, summarize via Ollama/Claude/OpenAI, identify speakers"
  homepage "https://github.com/tigger04/transcribe-recording"
  url "https://github.com/tigger04/transcribe-recording/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "1143d75596208fbe26e8c11da949080b6fcef3155e9bf839348c520025b60f2e"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on "ffmpeg"
  depends_on "ollama"
  depends_on "whisper-cpp"

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/transcribe-summarize"
    pkgshare.install "scripts/diarize.py"
  end

  def post_install
    # Pull mistral model so it works out of the box
    system "ollama", "pull", "mistral"
  end

  def caveats
    <<~EOS
      Ollama and the mistral model have been installed.

      To use local LLM summarization (no API key needed):
        brew services start ollama
        export OLLAMA_MODEL="mistral"
        transcribe-summarize --llm ollama meeting.m4a

      Or use cloud LLM providers:
        export ANTHROPIC_API_KEY="your_key"  # Claude (default)
        export OPENAI_API_KEY="your_key"     # OpenAI

      For speaker diarization (optional):
        1. Create account at https://huggingface.co
        2. Accept license at https://huggingface.co/pyannote/speaker-diarization-3.1
        3. Generate token at https://huggingface.co/settings/tokens
        4. Set: export HF_TOKEN="your_token"
    EOS
  end

  test do
    assert_match "transcribe-summarize", shell_output("#{bin}/transcribe-summarize --version")
  end
end
