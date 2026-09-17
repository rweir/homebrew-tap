#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "ripper"
require "tmpdir"

# This deliberately accepts only the simple, single-architecture coop cask.
# Parse Ruby as data: never load/eval the proposed cask or run its binaries.
module CoopProvenance
  class Error < StandardError; end

  module_function

  def call(node)
    case node
    in [:command, [:@ident, name, _], arguments]
      [name, arguments_list(arguments)]
    in [:method_add_arg, [:fcall, [:@ident, name, _]], arguments]
      arguments = arguments[1] if arguments[0] == :arg_paren
      [name, arguments.empty? ? [] : arguments_list(arguments)]
    else
      raise Error, "Unsupported cask expression"
    end
  end

  def arguments_list(node)
    case node
    in [:args_add_block, Array => arguments, false]
      arguments
    else
      raise Error, "Unsupported cask arguments"
    end
  end

  def block_body(node)
    case node
    in [:do_block, nil, [:bodystmt, Array => statements, nil, nil, nil]]
      statements.reject { |statement| statement == [:void_stmt] }
    else
      raise Error, "Unsupported cask block"
    end
  end

  def string(node, version: nil)
    unless node.is_a?(Array) && node[0] == :string_literal && node.dig(1, 0) == :string_content
      raise Error, "Expected a literal string"
    end

    node[1].drop(1).map do |part|
      case part
      in [:@tstring_content, value, _]
        raise Error, "Escaped strings are not supported" if value.include?("\\")
        value
      in [:string_embexpr, [[:vcall, [:@ident, "version", _]]]]
        raise Error, "Version interpolation is not allowed here" unless version
        version
      else
        raise Error, "Only version interpolation is supported"
      end
    end.join
  end

  def validate_livecheck(node)
    block_body(node).each do |statement|
      name, arguments = call(statement)
      raise Error, "Unsupported livecheck arguments" unless arguments.length == 1

      case [name, arguments.first]
      in ["url", [:symbol_literal, [:symbol, [:@ident, "url", _]]]]
        next
      in ["regex", [:regexp_literal, Array => parts, [:@regexp_end, _, _]]]
        unless parts.all? { |part| part[0] == :@tstring_content }
          raise Error, "Dynamic livecheck regex is not supported"
        end
      else
        raise Error, "Unsupported livecheck expression"
      end
    end
  end

  def parse(source)
    case Ripper.sexp(source)
    in [:program, [[:method_add_block, declaration, body]]]
      name, arguments = call(declaration)
      unless name == "cask" && arguments.length == 1 && string(arguments.first) == "coop"
        raise Error, "Expected exactly one coop cask"
      end
    else
      raise Error, "Expected exactly one coop cask"
    end

    fields = {}
    seen_livecheck = false
    block_body(body).each do |statement|
      if statement[0] == :method_add_block
        name, arguments = call(statement[1])
        unless name == "livecheck" && arguments.empty? && !seen_livecheck
          raise Error, "Unsupported or duplicate cask block"
        end
        validate_livecheck(statement[2])
        seen_livecheck = true
        next
      end

      name, arguments = call(statement)
      unless %w[version sha256 url name desc homepage binary].include?(name) && arguments.length == 1
        raise Error, "Unsupported cask stanza: #{name}"
      end
      version = fields["version"] if %w[url binary].include?(name)
      value = string(arguments.first, version: version)
      next if name == "binary"

      raise Error, "Duplicate cask stanza: #{name}" if fields.key?(name)
      fields[name] = value
    end

    version = fields.fetch("version") { raise Error, "Missing version" }
    checksum = fields.fetch("sha256") { raise Error, "Missing SHA-256" }
    url = fields.fetch("url") { raise Error, "Missing download URL" }
    raise Error, "Expected a numeric release version" unless version.match?(/\A\d+(?:\.\d+)+\z/)
    raise Error, "Expected a SHA-256 checksum" unless checksum.match?(/\A[0-9a-f]{64}\z/)

    expected_url = "https://github.com/trailofbits/coop/releases/download/v#{version}/" \
                   "coop-v#{version}-aarch64-apple-darwin.tar.gz"
    raise Error, "Unexpected coop release URL: #{url}" unless url == expected_url

    { version: version, sha256: checksum, url: url }
  end

  def run_command(*arguments)
    stdout, stderr, status = Open3.capture3(*arguments)
    raise Error, "#{arguments.first} failed: #{stderr.strip}" unless status.success?
    stdout
  end

  def download(url, destination)
    run_command("curl", "--fail", "--silent", "--show-error", "--location",
                "--proto", "=https", "--proto-redir", "=https",
                "--connect-timeout", "15", "--max-time", "120", "--retry", "2",
                "--output", destination, url)
  end

  def verify_files(metadata, archive, bundle, command: method(:run_command))
    unless Digest::SHA256.file(archive).hexdigest == metadata.fetch(:sha256)
      raise Error, "Archive SHA-256 does not match the cask"
    end

    bundles = File.readlines(bundle).reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
    unless !bundles.empty? && bundles.all? { |entry| entry.is_a?(Hash) && entry["dsseEnvelope"].is_a?(Hash) }
      raise Error, "Empty or malformed attestation bundle"
    end

    output = command.call("gh", "attestation", "verify", archive,
                          "--bundle", bundle, "--repo", "trailofbits/coop",
                          "--source-ref", "refs/tags/v#{metadata.fetch(:version)}",
                          "--signer-workflow", "trailofbits/coop/.github/workflows/release.yml",
                          "--deny-self-hosted-runners", "--format", "json")
    results = JSON.parse(output)
    unless results.is_a?(Array) && results.any? do |result|
      next false unless result.is_a?(Hash)
      subjects = result.dig("verificationResult", "statement", "subject")
      subjects.is_a?(Array) && subjects.any? do |subject|
        subject.is_a?(Hash) && subject.dig("digest", "sha256") == metadata.fetch(:sha256)
      end
    end
      raise Error, "No verified attestation covers the proposed checksum"
    end
  rescue JSON::ParserError, TypeError => e
    raise Error, "Malformed attestation data: #{e.message}"
  end

  def verify(cask_file)
    metadata = parse(File.read(cask_file))
    Dir.mktmpdir("coop-provenance-") do |directory|
      archive = File.join(directory, "coop.tar.gz")
      bundle = File.join(directory, "attestations.jsonl")
      download(metadata.fetch(:url), archive)
      download("https://github.com/trailofbits/coop/releases/download/" \
               "v#{metadata.fetch(:version)}/attestations.jsonl", bundle)
      verify_files(metadata, archive, bundle)
    end
    puts "Verified coop #{metadata.fetch(:version)}: #{metadata.fetch(:sha256)}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise CoopProvenance::Error, "Usage: ruby #{$PROGRAM_NAME} Casks/coop.rb" unless ARGV.length == 1
    CoopProvenance.verify(ARGV.first)
  rescue CoopProvenance::Error, SystemCallError => e
    warn "Provenance verification failed: #{e.message}"
    exit 1
  end
end
