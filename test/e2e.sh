#!/usr/bin/env bash
# End-to-end test for `swap`, fully hermetic: real `claude` and `security` are
# replaced by stubs, and a throwaway vault is used. Touches NOTHING on the host
# Keychain or your real credentials.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SWAP="$REPO/swap"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PATH="$HERE/stubs:$PATH"
chmod +x "$HERE/stubs/claude" "$HERE/stubs/security" "$SWAP"
export FAKE_KC="$WORK/keychain.slot"
export SWAP_VAULT="$WORK/vault"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
check(){ # check "desc" actual expected
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi
}
contains(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }

echo "== setup =="
"$SWAP" add work     --email work@example.com     --browser default >/dev/null
"$SWAP" add personal --email personal@example.com  --browser default >/dev/null
check "two accounts registered" "$("$SWAP" list | grep -c example.com)" "2"

echo "== login work (browser OAuth -> cached) =="
"$SWAP" login work >/dev/null
contains "work credential cached" "$(cat "$SWAP_VAULT/work.keychain")" "fake-work@example.com"
check "active is work after login" "$(cat "$SWAP_VAULT/.active")" "work"

echo "== login personal =="
"$SWAP" login personal >/dev/null
contains "personal credential cached" "$(cat "$SWAP_VAULT/personal.keychain")" "fake-personal@example.com"
check "active is personal after login" "$(cat "$SWAP_VAULT/.active")" "personal"

echo "== use work (instant restore, no browser) =="
"$SWAP" use work >/dev/null
check "active is work after use" "$(cat "$SWAP_VAULT/.active")" "work"
check "keychain slot == work's cached blob" "$(cat "$FAKE_KC")" "$(cat "$SWAP_VAULT/work.keychain")"
check "which reports work email" "$("$SWAP" which)" "work@example.com (work)"

echo "== interactive swap (pick personal by name, Enter=keep browser) =="
printf 'personal\n\n' | "$SWAP" >/dev/null
check "active is personal after interactive swap" "$(cat "$SWAP_VAULT/.active")" "personal"
check "keychain slot == personal's cached blob" "$(cat "$FAKE_KC")" "$(cat "$SWAP_VAULT/personal.keychain")"

echo "== save snapshots the live credential =="
"$SWAP" add snap --email snap@example.com >/dev/null
"$SWAP" save snap >/dev/null   # live slot currently holds personal's blob
contains "snap snapshot taken from live slot" "$(cat "$SWAP_VAULT/snap.keychain")" "fake-personal@example.com"

echo "== remove forgets the account + its cache =="
"$SWAP" remove snap >/dev/null
[ ! -f "$SWAP_VAULT/snap.keychain" ] && ok "snap cache removed" || bad "snap cache lingered"

echo ""
echo "passed=$pass failed=$fail"
if [ "$fail" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; exit 1; fi
