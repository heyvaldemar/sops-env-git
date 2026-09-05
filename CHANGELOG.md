# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-05

### Added

- **A sync that compares values, not bytes.** sops drops blank lines, so a
  byte-for-byte round trip reports every file as differing forever, and an
  alarm that always fires is one nobody reads. `--check` reports drift by
  variable name and never prints a value.
- **Every call passes `--input-type dotenv --output-type dotenv`.** sops picks
  its parser from the extension, does not know `.sops`, falls back to JSON and
  dies on the first comment line.
- **A pre-commit hook that rejects by filename before reading a byte**, then by
  a narrow set of credential shapes. A `.gitignore` with a negation beside an
  exclusion is exactly where `git add -f` slips a plaintext file through, and a
  filename cannot be argued with.
- **Nineteen scenarios for the hook, in both directions.** Twelve real
  credential shapes it must reject, seven benign ones it must accept —
  including a `sudoers` NOPASSWD line and an ordinary https URL, which are the
  false positives that got the previous version widened until it caught
  nothing.
- **Eight scenarios for the sync**, against real sops and age.

### Notes

- Comments are not encrypted, on purpose: it is what makes a diff readable. It
  also means a token pasted into one goes to the remote in the clear, so the
  hook scans comments too.
- Each machine needs its own key. One key across two hosts means compromising
  either opens the secrets of both.

### Found while writing the tests

- **A pattern beginning with a dash was never matched.** `grep -E "$p"` takes
  `-----BEGIN ... PRIVATE KEY-----` for an option. It needs `-e`, and without
  it the rule was invisible in a green run.
- **The token length rule was too strict to fire** on anything but an exact
  length.
- **GitHub's own push protection refused the first push**, because a suite that
  tests a secret detector necessarily contains strings shaped exactly like
  secrets. The fixtures are now assembled at runtime from pieces: the hook
  still receives the complete credential and still has to catch it, and the
  repository contains no literal that looks like one. Allowlisting them would
  have been one more exception in a project whose argument is that exceptions
  are where detectors go to die.
- **The drift report named no keys on busybox.** It parsed `diff` output, whose
  format varies between implementations; it now compares key by key and cannot
  print an empty list while looking like it worked.

[Unreleased]: https://github.com/heyvaldemar/sops-env-git/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/sops-env-git/releases/tag/v1.0.0
