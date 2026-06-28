---
name: swap
description: How Claude Code authentication works on macOS and how to run or switch between multiple Claude subscriptions. Use when the user wants to add/switch/list Claude accounts, asks why signing into a second subscription logged them out of the first, mentions swap, asks about the "Claude Code-credentials" Keychain item, OAuth token refresh, or running multiple Claude Code accounts at once.
---

# swap — multiple Claude subscriptions on one Mac

## 1. How Claude Code authentication works

Claude Code signs in with **OAuth**. The resulting credential is a JSON blob:

```json
{
  "accessToken":  "...",          // short-lived bearer token
  "refreshToken": "...",          // long-lived; mints new access tokens
  "expiresAt":    1774276124547,  // accessToken expiry, epoch ms
  "scopes":       ["user:inference", "user:profile"],
  "subscriptionType": "max"
}
```

On macOS this blob is stored in the **login Keychain**, not a file:

- Service name: `Claude Code-credentials`
- Account: the signed-in email

Inspect it directly:

```bash
security find-generic-password -s "Claude Code-credentials" -w
```

**Token refresh:** when `accessToken` expires, Claude Code automatically uses
`refreshToken` to mint a fresh one and rewrites the Keychain item. This is why a
saved credential whose `expiresAt` is in the past **still works** after import —
as long as its `refreshToken` is still valid, the next `claude` launch refreshes
it. Refreshing rotates the refresh token, so the same credential cannot be
actively refreshed on two machines indefinitely; the last machine to refresh
wins.

**The single-slot problem:** there is exactly one `Claude Code-credentials` item.
Signing into a second subscription **overwrites** the first. Switching back
requires another full browser OAuth flow.

## 2. What swap does

`swap` backs up each account's Keychain credential into a local vault and
restores it on demand — turning a browser re-login into an instant local swap.

```
swap add <name> --email <email> [--browser <app>]   register an account
swap login <name>      one-time browser OAuth, then cache the credential
swap use <name>        restore that account's credential (instant)
swap save <name>       re-cache the current live credential
swap which             show the active account
swap list              list configured accounts
swap remove <name>     forget an account
```

Typical setup:

```bash
swap add work     --email you@company.com --browser Chrome
swap add personal --email you@example.com --browser Safari
swap login work
swap login personal
swap use work       # restart `claude` to pick it up
```

### Mechanics

- **save / login** read the credential via `security find-generic-password` and
  write it to `<vault>/<name>.keychain` (mode 600).
- **use / restore** purge every `Claude Code-credentials` item, then re-add the
  saved blob with `security add-generic-password -U`. A stale item left behind
  can shadow the intended account, so the purge is essential.
- `--browser` routes the OAuth URL to a specific app by setting `BROWSER` to a
  tiny opener script (`open -a "<app>"`), so each account logs in under the right
  browser profile. The value is stored per-account in `accounts.json` and used
  only on the login path; restoring a cached credential is browser-independent.
- The interactive picker uses **no hardcoded browser list**. It runs
  `lsregister -dump` and keeps the top-level applications whose `claimed schemes`
  include both `http:` and `https:` — i.e. the apps macOS itself would offer as a
  default web browser. Browsers nested inside another `.app` and cached/throwaway
  copies (e.g. under `~/Library/Caches`) are filtered out, and the result is
  sorted for deterministic ordering. `SWAP_LSREGISTER` overrides the lsregister
  path for testing.

Vault location: `~/.config/swap` (override with `SWAP_VAULT`).

## 3. Sequential swap vs. concurrent profiles

`swap` is **sequential**: one default profile, swapped in place. Restart
`claude` after each `use`.

To run **two or more accounts at the same time**, give each its own profile
directory via `CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_CONFIG_DIR=~/.claude            claude   # default profile
CLAUDE_CONFIG_DIR=~/.claude-secondary  claude   # second profile, concurrently
```

macOS isolates the credentials automatically: the Keychain service name is
derived from the config dir —

```
Claude Code-credentials-<first 8 hex of sha256(CONFIG_DIR)>
```

— so different config dirs map to different Keychain items and there are **no
token-refresh races** between concurrent accounts. Each profile dir keeps its
own `.claude.json` (which holds the `oauthAccount`), `projects/`, `todos/`, and
history; shared assets (skills, settings) can be symlinked in.

`swap` deliberately manages **only** the default, unsuffixed
`Claude Code-credentials` item and leaves the per-config suffixed items alone.

## 4. Troubleshooting

- **`User interaction is not allowed` (over SSH):** the login Keychain is locked.
  Run `security unlock-keychain` first (or work in a local GUI session) before
  `swap use`.
- **`which` shows `none` after `use`:** the `security add-generic-password` step
  failed (usually a locked Keychain) — see above.
- **Imported credential is "expired":** expected. If the `refreshToken` is still
  valid, the next `claude` launch refreshes it. If login is still rejected, the
  refresh token was revoked — do a fresh `swap login <name>`.
- **Wrong account keeps coming back:** a stale Keychain item is shadowing the
  swap. `swap use` purges them; if doing it by hand, delete every
  `Claude Code-credentials` item first.
