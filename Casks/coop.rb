cask "coop" do
  version "0.6.0"
  sha256 "2eb045bbbb24e25c995500f93146eea5ee866595f9042ad441cb930d7ada3ed6"

  # Where to download the binary from
  url "https://github.com/trailofbits/coop/releases/download/v#{version}/coop-v#{version}-aarch64-apple-darwin.tar.gz"
  name "coop"
  desc "Isolated VM environment for running Claude Code and Codex"
  homepage "https://github.com/trailofbits/coop"

  # binaries are in a subdirectory inside the tarball, `brew` will use
  # the basename as the target
  binary "coop-v#{version}-aarch64-apple-darwin/coop"
  binary "coop-v#{version}-aarch64-apple-darwin/coop-proxy"

  # Use the templated `url` field above to find other versions
  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

end
