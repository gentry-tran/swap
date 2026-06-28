#!/usr/bin/env bash
# Per-command unit tests for swap. Exercises every command + its error paths.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
init_sandbox

echo "## help / usage / dispatch"
run - help
t_rc "help rc0" 0;            t_has "help shows commands" "Commands:"
run - --help;                t_has "--help alias" "Commands:"
run - boguscmd
t_rc "unknown cmd rc1" 1;     t_has "unknown cmd message" "Unknown command"

echo "## add"
fresh
run - add work --email w@example.com --browser Chrome
t_rc "add rc0" 0;             t_has "add confirms" "Added account 'work'"
t_eq "add stores email"   "$(acct_field work email)"   "w@example.com"
t_eq "add stores browser" "$(acct_field work browser)" "Chrome"
run - add nobrow --email n@example.com
t_eq "add default browser" "$(acct_field nobrow browser)" "default"
run - add --email noNameOnly@example.com
t_rc "add without name rc1" 1; t_has "add name usage" "Usage:"
fresh
run - add work
t_rc "add without email rc1" 1; t_has "add email usage" "Usage:"

echo "## list"
fresh
run - list
t_has "empty list message" "No accounts configured"
run - add work --email w@example.com >/dev/null
run - add "e@example.com" --email "e@example.com" >/dev/null   # name == email
run - list
t_has "list shows name(email)" "work (w@example.com)"
t_count "list email shown once when name==email" "$OUT" "e@example.com" 1
t_hasnot "list no double email" "e@example.com (e@example.com)"

echo "## login"
fresh
run - add work --email w@example.com --browser default >/dev/null
run - login work
t_rc "login rc0" 0
t_file "login wrote keychain"  "$SWAP_VAULT/work.keychain"
t_filehas "login cached blob"  "$SWAP_VAULT/work.keychain" "fake-w@example.com"
t_eq "login set active" "$(cat "$SWAP_VAULT/.active")" "work"
run - add brow --email b@example.com --browser Safari >/dev/null
run - login brow
t_rc "login w/ named browser rc0" 0
t_filehas "login(browser) cached" "$SWAP_VAULT/brow.keychain" "fake-b@example.com"
run - login ghost
t_rc "login unknown rc1" 1;   t_has "login unknown msg" "not found"

echo "## save"
fresh
run - add work --email w@example.com >/dev/null
# put a live credential in the (fake) keychain slot, then snapshot it
SWAP_VAULT="$SWAP_VAULT" "$SWAP" login work >/dev/null   # populates slot+vault
rm -f "$SWAP_VAULT/work.keychain"                        # drop cache, keep live slot
run - save work
t_rc "save rc0" 0
t_file "save rewrote keychain" "$SWAP_VAULT/work.keychain"
t_filehas "save snapshot content" "$SWAP_VAULT/work.keychain" "fake-w@example.com"
fresh
run - add empty --email e@example.com >/dev/null   # no live slot
run - save empty
t_nofile "save with no live cred makes no file" "$SWAP_VAULT/empty.keychain"
t_has "save with no live cred warns" "No credentials found"
run - save ghost
t_rc "save unknown rc1" 1

echo "## use / restore"
fresh
run - add work --email w@example.com >/dev/null
run - login work >/dev/null
printf '' > "$FAKE_KC"           # clear keychain slot
run - use work
t_rc "use rc0" 0
t_eq "use set active" "$(cat "$SWAP_VAULT/.active")" "work"
t_eq "use restored slot == vault blob" "$(cat "$FAKE_KC")" "$(cat "$SWAP_VAULT/work.keychain")"
run - add nocred --email nc@example.com >/dev/null
run - use nocred
t_rc "use without saved creds rc1" 1; t_has "use no-creds msg" "No saved credentials"
run - use ghost
t_rc "use unknown rc1" 1

echo "## which"
fresh
run - which
t_eq "which none" "$OUT" "none"
run - add work --email w@example.com >/dev/null
run - login work >/dev/null
run - which
t_eq "which name!=email shows email(name)" "$OUT" "w@example.com (work)"
run - add "self@example.com" --email "self@example.com" >/dev/null
run - login "self@example.com" >/dev/null
run - which
t_eq "which name==email shows email only" "$OUT" "self@example.com"

echo "## remove"
fresh
run - add work --email w@example.com >/dev/null
run - login work >/dev/null
t_file "pre-remove keychain exists" "$SWAP_VAULT/work.keychain"
run - remove work
t_rc "remove rc0" 0;          t_has "remove confirms" "Removed account 'work'"
t_eq "remove cleared registry" "$(acct_field work email)" ""
t_nofile "remove deleted keychain" "$SWAP_VAULT/work.keychain"
run - remove ghost
t_rc "remove nonexistent rc0 (idempotent)" 0

echo "## swap (interactive)"
fresh
run - swap   # no accounts
t_rc "swap empty rc1" 1;      t_has "swap empty msg" "No accounts yet"
# two accounts, both with cached creds
run - add work     --email w@example.com --browser Safari   >/dev/null
run - add personal --email p@example.com --browser Safari   >/dev/null
run - login work >/dev/null
run - login personal >/dev/null
# pick by name, keep browser (Enter)
run 'work\n\n' swap
t_rc "swap by name rc0" 0
t_eq "swap by name active" "$(cat "$SWAP_VAULT/.active")" "work"
t_eq "swap by name slot restored" "$(cat "$FAKE_KC")" "$(cat "$SWAP_VAULT/work.keychain")"
t_eq "swap keep-browser unchanged" "$(acct_field work browser)" "Safari"
# pick by number (sorted: personal=1, work=2) + choose browser #2 (Google Chrome from stub)
run 'personal\n2\n' swap
t_eq "swap by number active" "$(cat "$SWAP_VAULT/.active")" "personal"
t_eq "swap browser pick #2 -> Google Chrome" "$(acct_field personal browser)" "Google Chrome"
t_has "swap menu lists detected browsers" "detected on this Mac"
# invalid account selection
run 'nope\n' swap
t_rc "swap invalid pick rc1" 1; t_has "swap invalid msg" "No such account"
# account with no cached cred -> falls through to login
fresh
run - add fresh1 --email f@example.com --browser Safari >/dev/null
run 'fresh1\n\n' swap
t_rc "swap needs-login rc0" 0
t_has "swap needs-login runs login" "to sign in"
t_file "swap needs-login cached cred" "$SWAP_VAULT/fresh1.keychain"

echo "## browser detection (LaunchServices-derived, filtered)"
DETECTED="$(cd "$REPO" && bash -c 'source <(sed -n "/^detect_browsers()/,/^}\$/p" swap); detect_browsers')"
t_eq "detect: Safari present"          "$(grep -c '^Safari$' <<<"$DETECTED")" "1"
t_eq "detect: Google Chrome present"   "$(grep -c '^Google Chrome$' <<<"$DETECTED")" "1"
t_eq "detect: Firefox present"         "$(grep -c '^Firefox$' <<<"$DETECTED")" "1"
t_eq "detect: nested helper filtered"  "$(grep -c '^Chromium$' <<<"$DETECTED")" "0"
t_eq "detect: cached copy filtered"    "$(grep -c '^Camoufox$' <<<"$DETECTED")" "0"
t_eq "detect: non-browser filtered"    "$(grep -c '^Mail$' <<<"$DETECTED")" "0"
t_eq "detect: exactly 3 real browsers" "$(grep -c . <<<"$DETECTED")" "3"
t_eq "detect: sorted deterministically" "$(printf '%s' "$DETECTED" | tr '\n' '|')" "Firefox|Google Chrome|Safari"

summary
