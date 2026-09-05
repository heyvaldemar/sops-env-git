#!/bin/bash
# Does the sync keep the encrypted copy honest?
#
# Needs sops and age on PATH. The CI job installs pinned versions; locally,
# run it in a container the same way (see the workflow).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT/sops-env-sync.sh"
WORK="$(mktemp -d)"
PASSED=0; FAILED=0
trap 'rm -rf "$WORK"' EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

command -v sops >/dev/null || { echo "sops not on PATH"; exit 1; }
command -v age-keygen >/dev/null || { echo "age-keygen not on PATH"; exit 1; }

export SOPS_AGE_KEY_FILE="$WORK/keys.txt"
age-keygen -o "$SOPS_AGE_KEY_FILE" 2>/dev/null
PUB="$(grep -oE 'age1[0-9a-z]+' "$SOPS_AGE_KEY_FILE" | head -1)"

mkdir -p "$WORK/repo/stack"
cd "$WORK/repo" || exit 1
git init -q; git config user.email t@e.com; git config user.name t
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: \.env$
    age: $PUB
    encrypted_regex: '^[A-Z0-9_]+$'
EOF
cat > stack/.env <<'EOF'
# the database password, rotated 2026-08-01
DB_PASSWORD=originalsecret

DB_USER=appuser
EOF

echo "=== sops env sync ==="
echo

# 1. first run encrypts
out="$(bash "$SYNC" 2>&1)"
if [ -f stack/.env.sops ]; then pass "the first run creates the encrypted copy"; else fail "no encrypted copy was written"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# 2. VALUES are encrypted and NAMES are not: a diff shows that a password
#    changed without showing what to.
if grep -q 'DB_PASSWORD=ENC\[' stack/.env.sops && ! grep -q 'originalsecret' stack/.env.sops; then
  pass "values are encrypted, names stay readable"
else
  fail "the encrypted file does not look right"; head -5 stack/.env.sops | sed 's/^/        /'
fi

# 3. THE ONE THAT MAKES THE ALARM USABLE. sops drops blank lines, so a
#    byte-for-byte comparison reports every file as differing forever.
out="$(bash "$SYNC" --check 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'all in step'; then
  pass "an unchanged file reports no drift, despite sops dropping blank lines"
else
  fail "a file nobody touched was reported as drifted"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# 4. a real change IS drift
sed -i.bak 's/originalsecret/rotatedsecret/' stack/.env && rm -f stack/.env.bak
out="$(bash "$SYNC" --check 2>&1)"; rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'DRIFT'; then
  pass "an edited value is reported as drift"
else
  fail "an edited value went unnoticed"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# 5. and the report names the KEY, never the value
if printf '%s' "$out" | grep -q 'DB_PASSWORD' && ! printf '%s' "$out" | grep -q 'rotatedsecret'; then
  pass "drift is reported by key name, without printing the secret"
else
  fail "the drift report leaked a value"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# 6. a comment-only edit is NOT drift: the secrets did not change
bash "$SYNC" >/dev/null 2>&1
printf '\n# a note added by a person\n' >> stack/.env
out="$(bash "$SYNC" --check 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then pass "editing a comment is not reported as a secret change"; else fail "a comment edit was reported as drift"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# 7. an unreadable encrypted file is called unreadable, not "in sync"
printf 'not sops output at all\n' > stack/.env.sops
out="$(bash "$SYNC" --check 2>&1)"; rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'UNREADABLE'; then
  pass "an encrypted copy that cannot be decrypted is reported, not skipped"
else
  fail "an undecryptable file was treated as fine"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# 8. no .env at all is an error, not a reassuring success
rm -f stack/.env stack/.env.sops
out="$(bash "$SYNC" --check 2>&1)"; rc=$?
if [ $rc -ne 0 ]; then pass "a repository with no .env fails instead of reporting all clear"; else fail "it reported success having found nothing"; fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
