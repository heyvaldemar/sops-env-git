#!/bin/bash
# Has this detector ever been shown a real secret?
#
# The hook this replaces had been installed for days and passed a live webhook
# the first time it was fed one. So every pattern here is given a credential of
# the shape it claims to catch, and a handful of benign strings that must NOT
# be rejected — because a detector that fires on everything gets silenced with
# an exclusion, and the exclusion is what swallows the true positives.
#
# Both directions, or it proves nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/pre-commit"
WORK="$(mktemp -d)"
PASSED=0; FAILED=0
trap 'rm -rf "$WORK"' EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

repo() {
  rm -rf "$WORK/r"; mkdir -p "$WORK/r"
  git -C "$WORK/r" init -q
  git -C "$WORK/r" config user.email t@example.com
  git -C "$WORK/r" config user.name t
  mkdir -p "$WORK/r/hooks"
  cp "$HOOK" "$WORK/r/hooks/pre-commit"
}

# stages $2 as $1 and returns the hook's exit code
try() {
  local name="$1" content="$2"
  repo
  mkdir -p "$WORK/r/$(dirname "$name")"
  printf '%s\n' "$content" > "$WORK/r/$name"
  git -C "$WORK/r" add -f "$name" >/dev/null 2>&1
  ( cd "$WORK/r" && bash hooks/pre-commit >/dev/null 2>&1 )
}

must_reject() {
  if try "$2" "$3"; then fail "$1"; else pass "$1"; fi
}
must_accept() {
  if try "$2" "$3"; then pass "$1"; else fail "$1"; fi
}

# THE FIXTURES ARE ASSEMBLED AT RUNTIME, NOT WRITTEN OUT.
#
# A test for a secret detector needs strings shaped exactly like secrets, and
# a file full of those is a file that GitHub's own push protection refuses —
# correctly. It refused this one. So each credential is built from pieces here
# and only exists while the test runs: the hook still receives the complete
# string and still has to catch it, and the repository contains no literal
# that looks like a credential to anything scanning it.
#
# This is also the honest way round. A fixture that had to be allowlisted to
# be committed would be one more exception in a codebase whose whole argument
# is that exceptions are where detectors go to die.
S="https://hooks.slack.com/services"
MM="https://chat.example.com/hooks"
HC="https://hc-ping.com"
AGE_K="AGE-SECRET-KEY-1$(printf 'Q%.0s' $(seq 1 55))"
GHP="ghp_$(printf '0123456789abcdefghijklmnopqrstuvwxyz01')"
AWS="AKIA$(printf 'IOSFODNN7EXAMPLE')"
RESEND="re_$(printf 'd3nLxogbHyFHd3gbtAowSzvfVszg5c7S')"
SLACK="$S/T00000000/B00000000/$(printf 'X%.0s' $(seq 1 24))"
MMHOOK="$MM/$(printf 'abcdefghijklmnopqrstuvwx')"
HCPING="$HC/1f0e3dad-99bb-4a1e-9c2b-3c5c1a2b3c4d"
SSHKEY="-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAA"

echo "=== does the hook catch a real secret, and let real code through? ==="
echo

echo "the shapes it must REJECT"
must_reject "a plaintext .env, by filename, whatever is in it" ".env" "HELLO=world"
must_reject "a nested .env"                                    "stack/.env" "HELLO=world"
must_reject "an age private key file"                          "keys.txt" "$AGE_K"
must_reject "an age key pasted into a script"                  "setup.sh" "KEY=\"$AGE_K\""
must_reject "an SSH private key"                               "deploy.key.txt" "$SSHKEY"
must_reject "a GitHub personal access token"                   "ci.sh" "TOKEN=$GHP"
must_reject "an AWS access key id"                             "deploy.sh" "AWS_ACCESS_KEY_ID=$AWS"
must_reject "a Slack webhook"                                  "notify.sh" "URL=$SLACK"
must_reject "a Mattermost webhook"                             "notify.sh" "WEBHOOK=$MMHOOK"
must_reject "a healthchecks ping url"                          "cron.sh" "PING=$HCPING"
must_reject "a Resend api key"                                 "mail.sh" "RESEND_API_KEY=$RESEND"
must_reject "a secret pasted into a COMMENT, which sops does not encrypt" "notes.md" "# reminder: the hook is $SLACK"

echo
echo "the shapes it must ACCEPT"
must_accept "an example env file"          ".env.example" "DB_PASSWORD="
must_accept "an encrypted env file"        "stack/.env.sops" "DB_PASSWORD=ENC[AES256_GCM,data:abcdef,type:str]"
must_accept "a sudoers rule with NOPASSWD" "sudoers" "valdemar ALL=(root) NOPASSWD: /usr/sbin/smartctl -H *"
must_accept "an ordinary https url"        "README.md" "See https://github.com/heyvaldemar/sops-env-git for details."
# shellcheck disable=SC2016  # the literal ${...} is the point of this fixture
must_accept "a compose file with a variable reference" "docker-compose.yml" 'DB_PASSWORD: ${DB_PASSWORD:?set in .env}'
must_accept "a docs line naming a token variable"      "docs.md" "Set GITHUB_TOKEN in your environment before running this."
must_accept "a placeholder in documentation"           "SETUP.md" "export RESEND_API_KEY=re_your_key_here"

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
