# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "digest"
require "json"

class CoopProvenanceTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/verify-coop-provenance.rb", __dir__)
  require SCRIPT if File.exist?(SCRIPT)

  SOURCE = <<~'RUBY'
    cask "coop" do
      version "1.2.3"
      sha256 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      url "https://github.com/trailofbits/coop/releases/download/v#{version}/coop-v#{version}-aarch64-apple-darwin.tar.gz"
      name "coop"
      desc "A command-line tool"
      homepage "https://github.com/trailofbits/coop"
      binary "coop-v#{version}-aarch64-apple-darwin/coop"
      binary "coop-v#{version}-aarch64-apple-darwin/coop-proxy"
      livecheck do
        url :url
        regex(/^v?(\d+(?:\.\d+)+)$/i)
      end
    end
  RUBY

  def setup
    assert File.exist?(SCRIPT), "The provenance verifier has not been implemented"
  end

  def test_reads_literal_fields_and_interpolates_only_version
    metadata = CoopProvenance.parse(SOURCE)
    assert_equal "1.2.3", metadata.fetch(:version)
    assert_equal "https://github.com/trailofbits/coop/releases/download/v1.2.3/coop-v1.2.3-aarch64-apple-darwin.tar.gz", metadata.fetch(:url)
  end

  def test_rejects_ambiguous_or_dynamic_casks
    invalid = [
      SOURCE.sub('version "1.2.3"', 'version "latest"'),
      SOURCE.sub('version "1.2.3"', "version \"1.2.3\"\n  version \"4.5.6\""),
      SOURCE.sub('version "1.2.3"', 'version ENV.fetch("VERSION")'),
      SOURCE.sub('sha256 "ba7816', 'sha256 "broken'),
      SOURCE.sub('trailofbits/coop/releases', 'someone/coop/releases'),
      SOURCE.sub('v#{version}/coop', 'v9.9.9/coop'),
      SOURCE.sub('#{version}', '#{system("false")}'),
      SOURCE.sub('cask "coop"', 'cask "another"'),
      SOURCE + "\n system(\"false\")",
      SOURCE.sub('  name "coop"', '  system("false")'),
      SOURCE.sub('    url :url', '    system("false")'),
      SOURCE.sub('    regex(', '    eval('),
      SOURCE.sub('  version "1.2.3"', '  version "1.2.3" if false'),
      SOURCE.sub('cask "coop" do', 'cask "coop" do |argument|'),
      SOURCE.sub('1.2.3', '1\\x2e2.3'),
      SOURCE.sub('  version "1.2.3"', '')
    ]
    invalid.each do |source|
      assert_raises(CoopProvenance::Error, source) { CoopProvenance.parse(source) }
    end
  end

  def with_files
    Dir.mktmpdir do |directory|
      archive = File.join(directory, "archive.tar.gz")
      bundle = File.join(directory, "attestations.jsonl")
      File.binwrite(archive, "abc")
      File.write(bundle, "{\"dsseEnvelope\":{}}\n")
      yield CoopProvenance.parse(SOURCE), archive, bundle
    end
  end

  def verification_result(digest)
    JSON.generate([{ "verificationResult" => { "statement" => {
      "subject" => [{ "digest" => { "sha256" => digest } }]
    } } }])
  end

  def test_verifies_matching_bytes_with_repository_tag_and_workflow_constraints
    with_files do |metadata, archive, bundle|
      invocation = nil
      command = lambda do |*args|
        invocation = args
        verification_result(metadata.fetch(:sha256))
      end
      CoopProvenance.verify_files(metadata, archive, bundle, command: command)
      assert_equal ["gh", "attestation", "verify", archive,
                    "--bundle", bundle, "--repo", "trailofbits/coop",
                    "--source-ref", "refs/tags/v1.2.3",
                    "--signer-workflow", "trailofbits/coop/.github/workflows/release.yml",
                    "--deny-self-hosted-runners", "--format", "json"], invocation
    end
  end

  def test_rejects_tampered_bytes_before_invoking_verifier
    with_files do |metadata, archive, bundle|
      File.binwrite(archive, "tampered")
      error = assert_raises(CoopProvenance::Error) do
        CoopProvenance.verify_files(metadata, archive, bundle,
                                    command: ->(*) { flunk "Must check checksum first" })
      end
      assert_match(/SHA-256/, error.message)
    end
  end

  def test_rejects_empty_or_malformed_bundles_before_invoking_verifier
    ["", " \n", "not json", "null\n", "[]\n"].each do |contents|
      with_files do |metadata, archive, bundle|
        File.write(bundle, contents)
        assert_raises(CoopProvenance::Error) do
          CoopProvenance.verify_files(metadata, archive, bundle,
                                      command: ->(*) { flunk "Must reject bundle first" })
        end
      end
    end
  end

  def test_rejects_failed_or_empty_verification
    ["", "[]", "null", "[{}]", verification_result("0" * 64)].each do |output|
      with_files do |metadata, archive, bundle|
        assert_raises(CoopProvenance::Error) do
          CoopProvenance.verify_files(metadata, archive, bundle, command: ->(*) { output })
        end
      end
    end
    with_files do |metadata, archive, bundle|
      assert_raises(CoopProvenance::Error) do
        CoopProvenance.verify_files(metadata, archive, bundle,
                                    command: ->(*) { raise CoopProvenance::Error, "verification failed" })
      end
    end
  end
end
