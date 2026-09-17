# Rweir Tap

## How do I install these formulae?

`brew install rweir/tap/<formula>`

Or `brew tap rweir/tap` and then `brew install <formula>`.

Or, in a `brew bundle` `Brewfile`:

```ruby
tap "rweir/tap"
brew "<formula>"
```

## Documentation

`brew help`, `man brew` or check [Homebrew's documentation](https://docs.brew.sh).

## coop

Install the upstream Apple Silicon macOS binaries with:

```sh
brew install --cask rweir/tap/coop
```

### Updating coop

1. Create a branch and update `version` and `sha256` in `Casks/coop.rb`.
2. Run the verifier from the tap root (requires Ruby 3.2+, curl and a current GitHub CLI):

   ```sh
   ruby scripts/verify-coop-provenance.rb Casks/coop.rb
   ```

3. Test installation on an Apple Silicon Mac, then commit and open a pull request.
4. Wait for `verify-coop-provenance` to pass before merging.

The verifier downloads the proposed archive, checks its SHA-256 against the cask
and verifies the release's `attestations.jsonl` using `gh attestation verify`.
It requires the `trailofbits/coop` repository, the proposed `refs/tags/vVERSION`
ref and `.github/workflows/release.yml` signing workflow on GitHub-hosted runners.
Missing or invalid attestations fail the check. The binaries are never executed
by the verifier. Verification can access the network for Sigstore trust data;
it does not need a personal GitHub token.

The parser supports this cask's current literal metadata and `#{version}` string
interpolation. Other executable Ruby constructs and different archive layouts
are rejected; supporting another platform requires an explicit verifier change.
Provenance establishes origin, not whether the software is free of vulnerabilities.
Changes to the verifier or workflow themselves still need review.

Run the verifier tests with `ruby test/verify-coop-provenance_test.rb` after
installing Minitest: `gem install --user-install --no-document minitest --version 6.0.6`.
CI runs the tests and real verification on every PR. This workflow does not
configure branch protection. You can make `verify-coop-provenance` a required
status check on `main` later to enforce verification before merging.
