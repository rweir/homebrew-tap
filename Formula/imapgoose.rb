class Imapgoose < Formula
  desc "Keep local Maildir directories synchronised with an IMAP server"
  homepage "https://git.sr.ht/~whynothugo/ImapGoose"
  url "https://git.sr.ht/~whynothugo/ImapGoose/archive/v0.5.5.tar.gz"
  sha256 "9f87ecdde549a64b10eedfa8e37fb939edf69d67b14acc889a70f5432568557e"
  license "ISC"

  livecheck do
    url :stable
  end

  depends_on "go" => :build
  depends_on "sqlite"

  deny_network_access!

  def fetch
    system "go", "mod", "download"
  end

  def install
    ENV["VERSION"] = version

    system "make", "build"
    system "make", "capcheck"

    bin.install "imapgoose"
    bin.install "capcheck" => "imapgoose-capcheck"
    man1.install "imapgoose.1"
    man5.install "imapgoose.conf.5"
    zsh_completion.install "contrib/_imapgoose"
  end

  test do
    assert_match "failed to open config file",
                 shell_output("#{bin}/imapgoose -c #{testpath}/missing.scfg 2>&1", 1)
  end
end
