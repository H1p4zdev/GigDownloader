class Gigdownloader < Formula
  desc "YouTube, Facebook, Instagram, X, TikTok and Threads video downloader (up to 8K)"
  homepage "https://github.com/xauusd25/GigDownloader"
  url "https://github.com/xauusd25/GigDownloader/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "3c9cc79362874caa24c2da5ffc8521288f4392a9df45908aba1b19025ac47e6b"
  license "MIT"

  depends_on "deno"        # JavaScript runtime yt-dlp needs for YouTube
  depends_on "ffmpeg"      # merging video+audio and MP3 conversion
  depends_on "python@3.12"

  def install
    venv = virtualenv_create(libexec, "python3.12")
    system libexec/"bin/python", "-m", "pip", "install", "--upgrade",
           "yt-dlp[default]", "yt-dlp-threads", buildpath.to_s
    bin.install_symlink libexec/"bin/gig", libexec/"bin/gigdownloader"
  end

  test do
    assert_match "GigDownloader", shell_output("#{bin}/gig --version")
  end
end
