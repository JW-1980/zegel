# Zegel Homebrew formula (improvement #103).
#
# Install with:
#   brew tap jw-1980/zegel
#   brew install zegel

class Zegel < Formula
  desc "Tamper-proof file container format CLI"
  homepage "https://github.com/jw-1980/zegel"
  license "Apache-2.0"
  version "1.3.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/jw-1980/zegel/releases/download/v1.3.0/zegel-1.3.0-macos-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    else
      url "https://github.com/jw-1980/zegel/releases/download/v1.3.0/zegel-1.3.0-macos-x64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/jw-1980/zegel/releases/download/v1.3.0/zegel-1.3.0-linux-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    else
      url "https://github.com/jw-1980/zegel/releases/download/v1.3.0/zegel-1.3.0-linux-x64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  def install
    bin.install "zegel"
  end

  test do
    assert_match "Zegel", shell_output("#{bin}/zegel --version")
  end
end
