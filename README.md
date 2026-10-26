# Rweir Tap

## How do I install these formulae?

`brew install rweir/tap/<formula>`

Or `brew tap rweir/tap` and then `brew install <formula>`.

Or, in a `brew bundle` `Brewfile`:

```ruby
tap "rweir/tap"
brew "<formula>"
```

## Formula

- `imapgoose` - IMAP<->Maildir syncing utility
- `atuin` - fork of upstream that restores TLSv1.3 support by using `rustls`
- `supersonic` - fork of upstream that works on MacOS 27, note you
  need to run `xattr -r -d com.apple.quarantine
  /Applications/Supersonic.app` after installation/update to make it
  executable
