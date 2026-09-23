cask "supersonic" do
  arch arm: "arm64", intel: "x64"

  version "0.22.1"
  sha256 arm:   "54c6bc05216f428a34fffeb739c982cae9d23ff423c8826e381a2ee6fde6d78a",
         intel: "983be4516e140b0691e47063f803c2e0b01eb886334480548c06a5fb694fc875"

  url "https://github.com/supersonic-app/supersonic/releases/download/v#{version}/Supersonic-#{version}-mac-#{arch}.zip"
  name "Supersonic"
  desc "Desktop client for self-hosted music servers"
  homepage "https://github.com/supersonic-app/supersonic"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  app "Supersonic.app"

  zap trash: [
    "~/Library/Application Support/supersonic",
    "~/Library/Caches/supersonic",
  ]
end
