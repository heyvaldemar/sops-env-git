# SOPS env in git

[![Tests](https://github.com/heyvaldemar/sops-env-git/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/sops-env-git/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Keep your `.env` files in git, encrypted, so a repository can rebuild a host instead of only describing one.

Compose reads `.env` in plain text and there is no way around that. So the repository holds `.env.sops` beside it, encrypted with an age key, and `sops-env-sync.sh` keeps the two in step. Only values are encrypted: a diff shows *that* a password changed without showing what to.

## Five things that cost time

**sops picks its parser from the file extension.** It does not know `.sops`, falls back to JSON, and dies on the first comment line. The first attempt at this encrypted thirteen files and could decrypt none of them. Every call here passes `--input-type dotenv --output-type dotenv`.

**sops drops blank lines**, so a byte-for-byte round trip reports every file as differing, forever. That alarm looks serious and means nothing, and an alarm that always fires is one nobody reads. The comparison here is over the assignment lines, sorted.

**Comments are not encrypted.** That is deliberate — it is what makes the file readable in a diff — but it means a token pasted into a comment as a note goes to the remote in the clear. The hook scans comments too.

**Each machine needs its own key.** One key across two hosts means compromising either opens the secrets of both, and removes any possibility of rotating one without the other.

**A `.gitignore` with a negation beside an exclusion is exactly where `git add -f` slips a plaintext file through.** The hook rejects by filename before it reads a byte, because a filename cannot be argued with.

## The question to ask any leak detector

Has it ever been shown a real secret?

The hook this replaces had been installed for days. Fed a live webhook, it passed it. Two independent faults:

`hc-ping\.com` inside a single-quoted shell string reaches grep as a literal backslash followed by any character, so it could never match `hc-ping.com`. A pattern that cannot match is invisible in a green run.

And a path exclusion added to silence `sudoers` false positives read `[:=][[:space:]]*"?/[A-Za-z0-9_./-]+` — the `:` in `https:` is a `[:=]`, so every URL in every file was excluded from the scan. That one is the worse of the two because it arrived as a *fix*: a false positive was silenced by widening an exclusion, and the exclusion swallowed the true positives. The two secrets that actually reached the mirror were exactly those two shapes, with the hook already installed.

So `tests/test-hook.sh` feeds it twelve real credential shapes and seven benign ones and fails if any is classified wrongly. Both directions, or it proves nothing. Writing that suite caught two live misses: a pattern beginning with a dash, which `grep` took for an option and never matched, and a token length rule too strict to fire.

## Install

```bash
# once per machine
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt

# once per repository
cp .sops.yaml.example .sops.yaml && $EDITOR .sops.yaml    # your PUBLIC key
cp .gitignore .gitignore.new && $EDITOR .gitignore.new    # merge into yours
install -m 755 sops-env-sync.sh /usr/local/bin/
install -m 755 hooks/pre-commit .git/hooks/pre-commit
```

Put the **private** key in your password manager. Losing it makes every encrypted file unreadable forever; committing it makes the encryption theatre, and git history keeps it after the delete.

## Use

```bash
sops-env-sync.sh --check    # report drift by key name, change nothing
sops-env-sync.sh            # bring the encrypted copies up to date
```

Call the sync from whatever commits your configuration, **before** the commit step. Docker reads the plaintext file, so both exist, and they drift the moment somebody edits one — invisibly, because one encrypted blob looks like any other.

`--check` names the variables that differ and never their values.

## What this does not do

It does not manage key rotation. Changing an age key means re-encrypting every file and the old key still decrypts everything in git history.

It does not protect against someone with read access to the host: the plaintext `.env` is right there, which is the whole reason it is gitignored rather than deleted.

It does not replace a secrets manager. This makes a git repository able to rebuild a host. A team that needs per-person access, auditing and revocation needs something else.

## Testing

`tests/test-hook.sh` runs the detector in both directions, nineteen cases. `tests/test-sync.sh` runs eight against real sops and age: values encrypted and names readable, an untouched file reporting no drift despite the dropped blank lines, a changed value reported by key name without printing it, a comment-only edit not counted as a secret change, an undecryptable copy reported rather than skipped, and a repository with no `.env` failing instead of reporting all clear.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
