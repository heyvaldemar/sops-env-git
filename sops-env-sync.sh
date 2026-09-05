#!/bin/bash
# sops-env-sync.sh — keep the encrypted copy of every .env in step with the
# plaintext one docker actually reads.
#
# WHY BOTH FILES EXIST. Compose reads `.env` in plain text; there is no way
# around that. So the repository holds `.env.sops` next to it, encrypted with
# an age key, and this keeps them in step. The moment someone edits one and not
# the other they drift, invisibly, because one encrypted blob looks like any
# other in a diff.
#
# Only VALUES are encrypted. A diff therefore shows THAT a password changed
# without showing what to, which is what makes the history reviewable.
#
#   sops-env-sync.sh            encrypt every .env whose values have changed
#   sops-env-sync.sh --check    report drift, change nothing, non-zero if any
#
# FIVE THINGS THAT COST TIME HERE, all of them handled below:
#
#   1. sops picks its parser from the file EXTENSION. It does not know `.sops`,
#      falls back to JSON, and dies on the first comment line. The first attempt
#      at this encrypted thirteen files and could decrypt none of them. Every
#      call passes --input-type dotenv --output-type dotenv.
#
#   2. sops drops blank lines, so a byte-for-byte round trip reports every file
#      as differing, forever. An alarm that fires always is one nobody reads.
#      Compare the ASSIGNMENTS, sorted, and ignore everything else.
#
#   3. COMMENTS ARE NOT ENCRYPTED. That is deliberate — it is what makes the
#      file readable — but it means a token pasted into a comment as a note
#      goes to the remote in the clear. The leak check below reads comments too.
#
#   4. Each machine needs its OWN key. One key across two hosts means
#      compromising either opens the secrets of both, and removes any
#      possibility of rotating one without the other.
#
#   5. `.gitignore` with an exclusion and a negation beside it is exactly where
#      `git add -f` slips a plaintext file through. The hook in hooks/ rejects
#      by FILENAME before it reads a single byte.
set -uo pipefail

MODE="${1:-}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SOPS="${SOPS_BIN:-sops}"

command -v "$SOPS" >/dev/null 2>&1 || { echo "error: $SOPS not found on PATH" >&2; exit 1; }
[ -f "$ROOT/.sops.yaml" ] || { echo "error: no .sops.yaml at $ROOT — see the README" >&2; exit 1; }

# The assignment lines only, sorted: the comparison that means "the secrets are
# the same" rather than "the bytes are the same".
values() { grep -vE '^\s*(#|$)' "$1" 2>/dev/null | sort; }

drift=0
changed=0
found=0

while IFS= read -r -d '' env; do
  found=$((found+1))
  enc="$env.sops"
  rel="${env#"$ROOT"/}"

  if [ ! -f "$enc" ]; then
    if [ "$MODE" = "--check" ]; then
      echo "MISSING  $rel.sops has never been created"
      drift=1
    else
      if "$SOPS" --input-type dotenv --output-type dotenv -e "$env" > "$enc"; then
        echo "encrypted $rel.sops"; changed=$((changed+1))
      else
        echo "error: could not encrypt $rel" >&2; drift=1
      fi
    fi
    continue
  fi

  a="$(values "$env")"
  b="$("$SOPS" --input-type dotenv --output-type dotenv -d "$enc" 2>/dev/null | grep -vE '^\s*(#|$)' | sort)"

  if [ -z "$b" ]; then
    echo "UNREADABLE  $rel.sops could not be decrypted — wrong key, or it was written without --input-type dotenv"
    drift=1
    continue
  fi

  if [ "$a" = "$b" ]; then
    [ "$MODE" = "--check" ] && echo "ok       $rel"
  else
    if [ "$MODE" = "--check" ]; then
      # The NAMES of the variables that differ, never the values. Compared
      # key by key with awk rather than by parsing diff output: diff's format
      # varies between implementations, and the first version of this printed
      # an empty list on busybox while looking like it worked.
      keys="$(printf '%s\n%s\n' "$a" "$b" | awk -F= 'NF{print $1}' | sort -u)"
      differing=""
      for k in $keys; do
        va="$(printf '%s\n' "$a" | awk -F= -v k="$k" '$1==k{print; exit}')"
        vb="$(printf '%s\n' "$b" | awk -F= -v k="$k" '$1==k{print; exit}')"
        [ "$va" = "$vb" ] || differing="$differing $k"
      done
      echo "DRIFT    $rel — differing keys:${differing:- (none named — the files differ in a way this cannot attribute)}"
      drift=1
    else
      if "$SOPS" --input-type dotenv --output-type dotenv -e "$env" > "$enc"; then
        echo "updated  $rel.sops"; changed=$((changed+1))
      else
        echo "error: could not encrypt $rel" >&2; drift=1
      fi
    fi
  fi
done < <(find "$ROOT" -name '.env' -not -path '*/.git/*' -print0 2>/dev/null)

if [ "$found" -eq 0 ]; then
  # Not a success. A repository with no .env at all is either misconfigured or
  # being run from the wrong directory, and either way saying "all in sync"
  # would be a lie of the most reassuring kind.
  echo "error: no .env files found under $ROOT" >&2
  exit 1
fi

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "$found .env files, all in step with their encrypted copies"
  exit "$drift"
fi
echo "$found .env files checked, $changed encrypted copies written"
exit "$drift"
