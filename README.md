```
███████╗██╗    ██╗ █████╗ ██████╗
██╔════╝██║    ██║██╔══██╗██╔══██╗
███████╗██║ █╗ ██║███████║██████╔╝
╚════██║██║███╗██║██╔══██║██╔═══╝
███████║╚███╔███╔╝██║  ██║██║
╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝
   instant Claude Code account switching for macOS
```

Juggle multiple [Claude Code](https://claude.com/claude-code) subscriptions on one
Mac and switch between them in one command — no browser re-login every time.

---

## The problem

Claude Code is single-account by design. Signing into a second subscription
**overwrites** the first, and switching back means another full browser OAuth
round-trip. `swap` makes switching instant by backing up and restoring each
account's credentials locally.

## How Claude Code authentication works

This is the important part — and the part most "switcher" scripts get wrong.
A signed-in account is **two pieces of state**, and *both* must match:

| # | What | Where | Keyed by |
|---|------|-------|----------|
| 1 | **The token** (OAuth access + refresh) | macOS **login Keychain**, service `Claude Code-credentials` | the **macOS user name** (`whoami`) — *not* the email |
| 2 | **The identity** (email, account/org UUIDs) | **`~/.claude.json`** → `oauthAccount` block | — |

Two gotchas that each cause a confusing "please log in again":

- **Token keyed by the OS user, not the email.** If you restore the Keychain
  item under an account named after the email, `claude` looks it up by the OS
  user, doesn't find it, and forces a fresh login — even though the token is
  perfectly valid.
- **Identity lives in `~/.claude.json`, not the Keychain.** `claude auth status`
  reports the email from `oauthAccount`, *not* from the token. Swap the token but
  leave `oauthAccount` pointing at the old account and `claude` keeps showing the
  old account — "the auth didn't update."

`swap` handles both. Restoring an account writes the token to the Keychain under
`-a "$USER"` **and** restores that account's `oauthAccount` block into
`~/.claude.json`.

```
   vault (~/.config/swap)         macOS Keychain            ~/.claude.json
 ┌──────────────────────┐      ┌────────────────────┐    ┌────────────────┐
 │ work.keychain (token)│──┐   │ Claude Code-creds  │    │  oauthAccount  │
 │ work.oauth.json (id) │  ├──▶│  acct = $USER      │ +  │  (identity)    │
 │ work.email           │  │   └────────────────────┘    └────────────────┘
 └──────────────────────┘  │            ▲                        ▲
            swap use work ──┘     token restored          identity restored
```

**Token refresh:** an `accessToken` whose `expiresAt` is in the past still works
if its `refreshToken` is valid — `claude` refreshes on launch. Refreshing rotates
the refresh token, so the same credential can't be live on two machines forever;
last machine to refresh wins.

**Rotation vs. stale backups:** because the refresh token rotates on every use, a
backup taken once goes stale as you keep using that account — restoring it later
would hand back a dead token and force a login. swap avoids this by re-saving the
**outgoing** account's live token right before it switches away (only when the
live identity matches that account), so each backup tracks the latest rotation.
Two more guards: `swap login` **refuses to save** if the browser signed you into a
different account than the one you asked for, and a switch only reports "still
valid" when the restored session's email actually matches the account you picked
(otherwise it does a real browser login).

## Install

```bash
git clone https://github.com/gentry-tran/swap.git ~/tools/swap
~/tools/swap/install.sh        # symlinks `swap` into ~/.local/bin
```

`swap` is a single self-contained script, so you can also grab just that:

```bash
curl -fsSL https://raw.githubusercontent.com/gentry-tran/swap/main/swap \
  -o ~/.local/bin/swap && chmod +x ~/.local/bin/swap
```

Make sure `~/.local/bin` is on your `PATH`. Requirements: macOS, `bash`,
`python3`, and Claude Code (`claude`) installed.

## Quick start

No accounts yet? Just run `swap`. With an empty vault it runs Claude's own
sign-in (`claude auth login`), reads the resulting email from
`claude auth status`, and registers that account automatically. Repeat once per
subscription — after that, switching is instant.

```bash
swap            # empty vault → sign in, auto-register
swap            # later → pick an account, switch instantly
```

## Usage

Run `swap` with no arguments for the interactive picker:

```text
$ swap
Choose an account to swap to:
  1) work            you@company.com                  [saved] (active)
  2) personal        you@example.com                  [saved]
Account # (or name): 2

✓ Auth still valid (you@example.com) — no browser sign-in needed. Restart 'claude'.
```

What happens when you pick an account:

1. **Restore** its token (Keychain) and identity (`oauthAccount`) — instant, local.
2. **Check** the session with `claude auth status`:
   - still valid (or just needs a routine token refresh) → done, **no browser**.
   - genuinely expired → open a browser to re-authenticate.
3. **Restart `claude`** — it comes up already signed into that account, no `/login`.

**Browser prompt only when needed.** swap uses the browser already saved on the
account and asks nothing. It prompts you to pick a browser *only* if a sign-in is
actually required *and* the account has no usable browser saved (none set, or the
saved one isn't installed). The options offered are **the browsers your Mac
actually registers** — derived at runtime from LaunchServices (the apps that
claim `http`/`https`, i.e. the set macOS offers as a default browser), with
nested helper browsers and cached copies filtered out. `swap browsers` prints it.

### Commands

| Command | What it does |
|---------|--------------|
| `swap` | Interactive. Empty vault → native `claude auth login` + auto-register. Otherwise pick an account → instant restore, browser re-auth only if expired |
| `swap add <name> --email <e> [--browser <app>]` | Register an account |
| `swap login <name>` | Browser OAuth, then cache token + identity |
| `swap use <name>` | Switch to a cached account (no prompts) |
| `swap save <name>` | Snapshot the current live token + identity into the vault |
| `swap list` | List configured accounts |
| `swap which` | Show the active account |
| `swap browsers` | List the browsers detected on this Mac |
| `swap remove <name>` | Forget an account |

`--browser` accepts any installed app name (`Safari`, `Google Chrome`,
`Brave Browser`, `Firefox`, `Arc`, …) or `default` (system default browser).

## Vault

State lives in `~/.config/swap` (override with `SWAP_VAULT`), chmod-600:

| File | Holds |
|------|-------|
| `accounts.json` | registry: `name -> { email, browser }` |
| `<name>.keychain` | the OAuth **token** blob |
| `<name>.oauth.json` | the `oauthAccount` **identity** block |
| `<name>.email` | the account email (display/metadata) |
| `.active` | name of the currently restored account |

The `.keychain` and `.oauth.json` files are live secrets — the vault is
chmod-600 and `.gitignore`d. Never commit or share them.

## Testing

Fully hermetic suite — `claude`, `security`, `open`/`lsregister` are stubbed and
a throwaway vault + config are used, so it never touches your real Keychain,
credentials, or `~/.claude.json`:

```bash
./test/run.sh        # unit (per-command) + e2e (integration)
```

Covers every command and the tricky bits: token keyed by `$USER`, `oauthAccount`
save/restore, the validity check, empty-vault bootstrap, and browser detection.

## Scope & limitations

- **macOS only** — depends on `security(1)`, the login Keychain, and `~/.claude.json`.
- Manages the **default** Claude Code profile. Concurrent profiles that set a
  custom `CLAUDE_CONFIG_DIR` use a separate `Claude Code-credentials-<hash>`
  Keychain item and their own config dir; those are intentionally left alone.
- **Over SSH** the login Keychain is often locked — run `security unlock-keychain`
  first, or switch in a local GUI session.

## License

MIT
