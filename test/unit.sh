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
t_eq "use keys keychain by macOS user (not email)" "$(cat "$FAKE_KC.acct")" "${USER:-$(id -un)}"
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
# --- empty vault bootstraps via claude auth login (no hand-entered account) ---
fresh
run '\n' swap                     # Enter = default browser, then native sign-in
t_rc "swap bootstrap rc0" 0
t_has "swap bootstrap signs in" "Signed in and saved"
t_eq "swap bootstrap registered account" "$(acct_field bootstrap@example.com email)" "bootstrap@example.com"
t_eq "swap bootstrap active" "$(cat "$SWAP_VAULT/.active")" "bootstrap@example.com"
t_file "swap bootstrap cached cred" "$SWAP_VAULT/bootstrap@example.com.keychain"

# --- valid cached account with a saved browser: restore, NO browser prompt ---
fresh
run - add work     --email w@example.com --browser Safari   >/dev/null
run - add personal --email p@example.com --browser Safari   >/dev/null
run - login work >/dev/null
run - login personal >/dev/null          # active=personal, slot=personal
run 'work\n' swap                          # only the account line — no browser prompt expected
t_rc "swap by name rc0" 0
t_eq "swap by name active" "$(cat "$SWAP_VAULT/.active")" "work"
t_eq "swap by name slot restored" "$(cat "$FAKE_KC")" "$(cat "$SWAP_VAULT/work.keychain")"
t_has "swap valid auth -> no browser" "Auth still valid"
t_hasnot "swap valid: no browser prompt" "Which browser"
t_eq "swap saved-browser untouched" "$(acct_field work browser)" "Safari"
run 'nope\n' swap                        # invalid account selection
t_rc "swap invalid pick rc1" 1; t_has "swap invalid msg" "No such account"

# --- expired session WITH a saved installed browser: re-auth, NO prompt ---
fresh
run - add exp --email exp@example.com --browser Safari >/dev/null
# A COMPLETE saved account (token + identity) whose token is expired and carries
# no refresh token. Both files must exist or it's treated as needs-login, not expired.
printf '%s' '{"claudeAiOauth":{"accessToken":"EXPIRED-TOKEN","expiresAt":0}}' > "$SWAP_VAULT/exp.keychain"
printf '%s' '{"emailAddress":"exp@example.com","accountUuid":"uuid-exp"}' > "$SWAP_VAULT/exp.oauth.json"
run 'exp\n' swap
t_rc "swap expired rc0" 0
t_has "swap expired announces re-auth" "is expired"
t_hasnot "swap expired: no prompt (browser saved)" "Which browser"
t_filehas "swap expired re-logged in" "$SWAP_VAULT/exp.keychain" "fake-exp@example.com"
t_eq "swap expired active" "$(cat "$SWAP_VAULT/.active")" "exp"

# --- needs-login WITH a saved installed browser: NO prompt ---
fresh
run - add fresh1 --email f@example.com --browser Safari >/dev/null
run 'fresh1\n' swap
t_rc "swap needs-login rc0" 0
t_hasnot "swap needs-login: no prompt (browser saved)" "Which browser"
t_has "swap needs-login runs login" "to sign in"
t_file "swap needs-login cached cred" "$SWAP_VAULT/fresh1.keychain"

# --- needs-login with saved browser NOT installed: DOES prompt, on this account ---
fresh
run - add br --email br@example.com --browser "Brave Browser" >/dev/null   # not in stub-detected set
run 'br\n2\n' swap                       # account, then browser #2 (Google Chrome)
t_rc "swap reprompt rc0" 0
t_has "swap reprompts when saved browser missing" "Which browser"
t_eq "swap reprompt saved new browser" "$(acct_field br browser)" "Google Chrome"
t_filehas "swap reprompt logged in" "$SWAP_VAULT/br.keychain" "fake-br@example.com"
t_eq "swap reprompt active" "$(cat "$SWAP_VAULT/.active")" "br"

# --- "default" browser counts as saved: NO prompt ---
fresh
run - add d1 --email d@example.com >/dev/null    # browser defaults to "default"
run 'd1\n' swap
t_rc "swap default-browser rc0" 0
t_hasnot "swap default-browser: no prompt" "Which browser"
t_file "swap default-browser logged in" "$SWAP_VAULT/d1.keychain"

echo "## identity (oauthAccount) saved + restored with the token"
cj_email(){ python3 -c "import json,os
try: print(json.load(open(os.environ['SWAP_CLAUDE_JSON'])).get('oauthAccount',{}).get('emailAddress',''))
except Exception: print('')"; }
fresh
run - add work --email w@example.com >/dev/null
run - login work >/dev/null                       # stub writes .claude.json oauthAccount=w + token
t_file "login saved identity block" "$SWAP_VAULT/work.oauth.json"
t_eq "login set identity in .claude.json" "$(cj_email)" "w@example.com"
# simulate a switch-away corrupting the identity, then restore it via use
python3 -c "import json,os;p=os.environ['SWAP_CLAUDE_JSON'];d=json.load(open(p));d['oauthAccount']['emailAddress']='STALE@example.com';json.dump(d,open(p,'w'))"
t_eq "identity corrupted pre-restore" "$(cj_email)" "STALE@example.com"
run - use work
t_eq "use restored identity (oauthAccount)" "$(cj_email)" "w@example.com"
# remove cleans the identity file too
run - remove work
t_nofile "remove deleted identity file" "$SWAP_VAULT/work.oauth.json"

echo "## snapshot-on-switch: outgoing account's rotated token is re-saved before leaving"
# Claude rotates the refresh token on use; without re-snapshotting the outgoing
# account, switching away then back restores a dead token. Verify the switch
# captures the live (rotated) token into the OUTGOING account's vault file.
fresh
run - add work     --email w@example.com >/dev/null
run - add personal --email p@example.com >/dev/null
run - login work     >/dev/null            # active=work, slot+vault hold work's first token
run - login personal >/dev/null            # active=personal
run - use work       >/dev/null            # back to work; active=work, live slot=work token
# Simulate Claude rotating work's token while work is live (new refresh token):
printf '{"claudeAiOauth":{"accessToken":"fake-w@example.com","refreshToken":"ROTATED","expiresAt":0}}' > "$FAKE_KC"
run - use personal                          # switch AWAY from work -> must re-save work first
t_rc "snapshot-on-switch rc0" 0
t_filehas "outgoing rotated token captured" "$SWAP_VAULT/work.keychain" "ROTATED"
t_eq "switched to personal" "$(cat "$SWAP_VAULT/.active")" "personal"
# Guard: don't write the wrong account's token into another's file. After the
# switch above the live slot belongs to personal; saving 'work' must NOT clobber it.
t_hasnot "personal vault not corrupted by work's token" "$(cat "$SWAP_VAULT/personal.keychain")" "ROTATED"

echo "## 'saved' requires BOTH token and identity (lone keychain = needs login)"
fresh
run - add half --email half@example.com --browser Safari >/dev/null
printf '{"claudeAiOauth":{"accessToken":"fake-half@example.com","refreshToken":"r","expiresAt":0}}' > "$SWAP_VAULT/half.keychain"
# keychain present but NO oauth.json -> not a complete account -> must run a login,
# not a silent (broken) restore.
run 'half\n' swap
t_rc "lone-keychain rc0" 0
t_has "lone keychain triggers login not restore" "to sign in"
t_file "lone-keychain login completed identity" "$SWAP_VAULT/half.oauth.json"

echo "## login refuses to save when the signed-in account != requested account"
fresh
run - add colum --email colum@example.com --browser Safari >/dev/null
# Browser is already signed into a DIFFERENT account (gmail), so the captured
# session is gmail even though we asked for colum. swap must refuse to save.
export STUB_FORCE_LOGIN_EMAIL="gmail@example.com"
run - login colum
unset STUB_FORCE_LOGIN_EMAIL
t_rc "mismatched login rc1" 1
t_has "mismatch refusal message" "Refusing to save"
t_nofile "mismatch did NOT write wrong keychain" "$SWAP_VAULT/colum.keychain"

echo "## switch verifies restored email matches the picked account (no false 'still valid')"
fresh
run - add a1 --email a1@example.com --browser Safari >/dev/null
run - add a2 --email a2@example.com --browser Safari >/dev/null
run - login a1 >/dev/null
run - login a2 >/dev/null            # active=a2, identity=a2
# Forge an a1 entry whose keychain+identity actually belong to a2 (wrong creds).
cp "$SWAP_VAULT/a2.keychain"   "$SWAP_VAULT/a1.keychain"
printf '%s' '{"emailAddress":"a2@example.com","accountUuid":"uuid-a2"}' > "$SWAP_VAULT/a1.oauth.json"
run 'a1\n' swap
# Restored session resolves to a2, not a1 -> must NOT claim "still valid"; must re-auth.
t_hasnot "no false still-valid on mismatch" "Auth still valid"
t_has "mismatch forces real login" "to sign in"

echo "## browser detection (LaunchServices-derived, filtered) via 'swap browsers'"
run - browsers
t_rc "browsers rc0" 0
t_eq "browsers: deterministic sorted set" "$(printf '%s' "$OUT" | tr '\n' '|')" "Firefox|Google Chrome|Safari"
t_has "browsers: Safari present"        "Safari"
t_has "browsers: Google Chrome present" "Google Chrome"
t_has "browsers: Firefox present"       "Firefox"
t_hasnot "browsers: nested helper filtered" "Chromium"
t_hasnot "browsers: cached copy filtered"   "Camoufox"
t_hasnot "browsers: non-browser filtered"   "Mail"

summary
