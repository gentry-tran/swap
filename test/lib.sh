#!/usr/bin/env bash
# Shared test harness for swap. Hermetic: stubs replace claude/security/open and
# a throwaway vault is used, so nothing touches the real Keychain or host config.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SWAP="$REPO/swap"

PASS=0; FAIL=0
declare -a FAILED=()

init_sandbox() {
  SANDBOX="$(mktemp -d)"
  export PATH="$HERE/stubs:$PATH"
  chmod +x "$HERE"/stubs/* "$SWAP" 2>/dev/null || true
  export FAKE_KC="$SANDBOX/slot"
  export SWAP_VAULT="$SANDBOX/vault"
  mkdir -p "$SWAP_VAULT"
  trap 'rm -rf "$SANDBOX"' EXIT
}

# Reset to an empty vault + empty keychain slot between tests.
fresh() {
  rm -rf "$SWAP_VAULT" "$FAKE_KC" "$FAKE_KC.acct"
  mkdir -p "$SWAP_VAULT"
}

# run "<stdin>" <args...>  ('-' = no stdin). Captures combined output -> OUT, rc -> RC.
run() {
  local input="$1"; shift
  if [ "$input" = "-" ]; then
    OUT="$("$SWAP" "$@" 2>&1)"; RC=$?
  else
    OUT="$(printf '%b' "$input" | "$SWAP" "$@" 2>&1)"; RC=$?
  fi
}

_ok() { PASS=$((PASS+1)); }
_no() { FAIL=$((FAIL+1)); FAILED+=("$1"); printf '  FAIL %s\n        %s\n' "$1" "${2:-}"; }

t_rc()      { [ "$RC" = "$2" ] && _ok || _no "$1" "rc=$RC want $2 | out=<$OUT>"; }
t_has()     { case "$OUT" in *"$2"*) _ok;; *) _no "$1" "missing '$2' in <$OUT>";; esac; }
t_hasnot()  { case "$OUT" in *"$2"*) _no "$1" "unexpected '$2' in <$OUT>";; *) _ok;; esac; }
t_eq()      { [ "$2" = "$3" ] && _ok || _no "$1" "got '$2' want '$3'"; }
t_file()    { [ -f "$2" ] && _ok || _no "$1" "missing file $2"; }
t_nofile()  { [ ! -e "$2" ] && _ok || _no "$1" "file should not exist: $2"; }
t_filehas() { case "$(cat "$2" 2>/dev/null)" in *"$3"*) _ok;; *) _no "$1" "file $2 lacks '$3'";; esac; }
t_count()   { # name haystack needle expected_count
  local c; c=$(grep -o -F "$3" <<<"$2" | wc -l | tr -d ' ')
  [ "$c" = "$4" ] && _ok || _no "$1" "count('$3')=$c want $4 in <$2>"; }

# Read a field from accounts.json for assertions.
acct_field() {
  SWAP_VAULT="$SWAP_VAULT" N="$1" F="$2" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["SWAP_VAULT"]) / "accounts.json"
d = json.loads(p.read_text()) if p.exists() else {}
print(d.get("accounts", {}).get(os.environ["N"], {}).get(os.environ["F"], ""))
PY
}

summary() {
  echo ""
  echo "================  PASS=$PASS  FAIL=$FAIL  ================"
  if [ "$FAIL" -ne 0 ]; then
    echo "Failed cases:"; printf '  - %s\n' "${FAILED[@]}"; exit 1
  fi
  echo "ALL TESTS PASSED"
}
