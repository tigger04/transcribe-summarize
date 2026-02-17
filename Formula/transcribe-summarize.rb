# ABOUTME: Homebrew formula for transcribe-summarize.
# ABOUTME: Builds from source. Python venv for diarization created on first use.

class TranscribeSummarize < Formula
  desc "Transcribe audio, generate subtitles, summarize via Ollama/Claude/OpenAI"
  homepage "https://github.com/tigger04/transcribe-summarize"
  url "https://github.com/tigger04/transcribe-summarize/archive/refs/tags/v0.2.18.tar.gz"
  sha256 "f668d3909a2a0b539dcaed2c056d383f88e254350dc783e036f9cb67cdfcf8a2"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on "ffmpeg"
  depends_on "ollama"
  depends_on "whisper-cpp"

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/transcribe"
    bin.install_symlink "transcribe" => "transcribe-summarize"
    pkgshare.install "scripts/diarize.py"
  end

  def post_install
    # Pull llama3.1:8b model so it works out of the box
    system "ollama", "pull", "llama3.1:8b"
  end

  def caveats
    <<~EOS
      The binary is now called `transcribe` with subcommands:
        transcribe summarize meeting.m4a   # Full pipeline (transcribe + summarize)
        transcribe srt meeting.m4a         # Generate SRT subtitles
        transcribe vtt meeting.m4a         # Generate WebVTT subtitles
        transcribe words meeting.m4a       # Word-by-word JSON with timestamps

      The old `transcribe-summarize` command still works but is deprecated.

      To use local LLM summarization (no API key needed):
        brew services start ollama
        export OLLAMA_MODEL="llama3.1:8b"
        transcribe summarize meeting.m4a

      Or use cloud LLM providers:
        export ANTHROPIC_API_KEY="your_key"  # Claude
        export OPENAI_API_KEY="your_key"     # OpenAI

      For speaker diarization (optional, works with all subcommands):
        transcribe srt --speakers "Alice,Bob" meeting.m4a
    EOS
  end

  test do
    assert_match "transcribe", shell_output("#{bin}/transcribe --version")
  end
end
