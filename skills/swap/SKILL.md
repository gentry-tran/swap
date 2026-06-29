---
name: swap
description: How Claude Code authentication works on macOS and how to run or switch between multiple Claude subscriptions with the `swap` tool. Use when the user wants to add/switch/list Claude accounts, asks why signing into a second subscription logged them out of the first, hits "please log in" / "auth didn't update" after switching, mentions swap, asks about the "Claude Code-credentials" Keychain item, the oauthAccount block in ~/.claude.json, OAuth token refresh, or running multiple Claude Code accounts at once.
---

# swap — multiple Claude subscriptions on one Mac

## 1. How Claude Code authentication works

A signed-in Claude Code account on macOS is **two pieces of state**. Both must
agree, or `claude` gets confused.

### (a) The token — macOS login Keychain

The OAuth credential blob:

```json
{
  "accessToken":  "...",          // short-lived bearer token
  "refreshToken": "...",          // long-lived; mints new access tokens
  "expiresAt":    1774276124547,  // accessToken expiry, epoch ms
  "scopes":       ["user:inference", "user:profile"],
  "subscriptionType": "max"
}
```

Stored in the login Keychain:

- **Service:** `Claude Code-credentials`
- **Account (`acct`):** the **macOS login user name** (`whoami`) — **NOT the
  email.** This trips everyone up. If the item is written with the email as its
  account attribute, `claude` (which looks it up by the OS user) won't find it
  and forces a fresh login, even with a valid token.

```bash
security find-generic-password -s "Claude Code-credentials" -g   # note acct = your macOS user
```

### (b) The identity — `~/.claude.json` → `oauthAccount`

```json
"oauthAccount": {
  "accountUuid": "...",
  "emailAddress": "you@example.com",
  "organizationUuid": "...",
  "organizationName": "...",
  "organizationType": "claude_max"
}
```

**`claude auth status` reports the email from `oauthAccount`, not from the
token.** So if you swap the Keychain token but leave `oauthAccount` on the
previous account, `claude` keeps reporting the old account — "the auth didn't
update." A correct switch updates **both** the token and `oauthAccount`.

### Token refresh

When `accessToken` expires, Claude Code uses `refreshToken` to mint a new one and
rewrites the Keychain item. So an imported credential whose `expiresAt` is in the
past **still works** if its refresh token is valid. Refreshing rotates the
refresh token → the same credential can't stay live on two machines forever; the
last to refresh wins.

### The single-slot problem

There is exactly one `Claude Code-credentials` item and one `oauthAccount`.
Signing into a second subscription overwrites both. That's what `swap` works
around.

## 2. What swap does

`swap` keeps a per-account backup of **both** pieces and restores them together.

```
swap                   interactive: pick account, switch (empty vault → sign in + register)
swap add <name> --email <email> [--browser <app>]   register an account
swap login <name>      one-time browser OAuth, then cache token + identity
swap use <name>        restore token + identity (instant, no prompts)
swap save <name>       re-cache the current live token + identity
swap which             show the active account
swap list              list configured accounts
swap browsers          list browsers detected on this Mac
swap remove <name>     forget an account
```

Bare `swap`:
- **Empty vault** → runs `claude auth login`, reads the signed-in email from
  `claude auth status --json`, and registers that account (named by its email).
- **Has accounts** → pick one → restore token + identity, then check
  `claude auth status`. Still valid (or just needs a routine refresh) → switch
  with **no browser**. Genuinely expired → open a browser to re-authenticate.

## 3. Mechanics

- **save / login** read the token via `security find-generic-password -a "$USER"`
  (with a service-only fallback) → `<vault>/<name>.keychain`, and copy the
  `oauthAccount` block out of `~/.claude.json` → `<vault>/<name>.oauth.json`.
- **use / restore** purge every `Claude Code-credentials` item, then re-add the
  saved token with `security add-generic-password -U -a "$USER"` (the macOS user,
  or `claude` won't find it), **and** write the saved `oauthAccount` back into
  `~/.claude.json`. Purging first prevents a stale item shadowing the new one.
- **validity check** (interactive `swap` only): after restoring, run
  `claude auth status --json`. Logged-in → done, no browser. Otherwise re-auth.
- **browser selection** is only consulted when a sign-in is actually needed and
  the account has no usable saved browser. The candidate list is **not
  hardcoded**: it runs `lsregister -dump` and keeps top-level apps whose
  `claimed schemes` include both `http:` and `https:` (the set macOS offers as a
  default browser), filtering out nested helper browsers and cached copies, and
  sorts for deterministic order. `--browser` then routes the OAuth URL with
  `open -a "<app>"`.
- Overrides for testing: `SWAP_VAULT`, `SWAP_LSREGISTER`, `SWAP_CLAUDE_JSON`.

## 4. Sequential swap vs. concurrent profiles

`swap` is **sequential**: one default profile, swapped in place. Restart `claude`
after each switch.

To run **two or more accounts at once**, give each its own profile dir via
`CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_CONFIG_DIR=~/.claude            claude   # default profile
CLAUDE_CONFIG_DIR=~/.claude-secondary  claude   # second profile, concurrently
```

macOS isolates credentials automatically: the Keychain service name is derived
from the config dir —

```
Claude Code-credentials-<first 8 hex of sha256(CONFIG_DIR)>
```

— so different config dirs → different Keychain items + their own `.claude.json`
(`oauthAccount`), with no token-refresh races. `swap` deliberately manages only
the **default**, unsuffixed item and leaves suffixed profiles alone.

## 5. Troubleshooting

- **"Please run /login" right after swapping (token looks valid):** the Keychain
  item was written under the wrong account attribute. It must be `-a "$USER"`
  (your macOS user), not the email. `swap use` does this; if doing it by hand,
  match the account attribute.
- **`claude` shows the *old* account after swapping:** `oauthAccount` in
  `~/.claude.json` wasn't updated. Restore it alongside the token (`swap use`
  does both).
- **`User interaction is not allowed` (over SSH):** the login Keychain is locked.
  Run `security unlock-keychain` first, or use a local GUI session.
- **Imported credential is "expired":** expected — if the refresh token is still
  valid, the next `claude` launch refreshes it. If login is still rejected, the
  refresh token was revoked → `swap login <name>` for a fresh sign-in.
- **Wrong account keeps returning:** a stale Keychain item is shadowing the swap.
  `swap use` purges them; by hand, delete every `Claude Code-credentials` item
  first.
