# swap

Instant account switching for [Claude Code](https://claude.com/claude-code) on macOS — juggle multiple Claude subscriptions without re-logging-in through the browser every time.

## The problem

Claude Code authenticates with a single OAuth credential stored in the macOS
login Keychain under the service name `Claude Code-credentials`. There is only
one slot, so signing into a second subscription **overwrites** the first.
Switching back means another full browser OAuth round-trip — every time.

## What it does

`swap` keeps a per-account backup of that Keychain credential in a local vault
and restores it on demand. Set your accounts up once; after that, switching is a
single instant command with no browser.

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
`python3`, and Claude Code (`claude`) already installed.

## Quick start

No accounts yet? Just run `swap` — with an empty vault it runs Claude's own
sign-in (`claude auth login`), then saves whatever account you logged into,
named by its email. Repeat for each subscription. After that, `swap` switches
between them instantly.

## Set up (one time per account)

You can also register accounts explicitly:

1. **Register** each subscription you use, with the browser its login should open in:

   ```bash
   swap add work     --email you@company.com --browser Chrome
   swap add personal --email you@example.com --browser Safari
   ```

2. **Log in** to each once. This opens the OAuth flow in the chosen browser and
   caches the credential into the vault:

   ```bash
   swap login work
   swap login personal
   ```

   Already signed into one account in Claude Code? Skip its login and just snapshot
   the live credential instead:

   ```bash
   swap add current --email you@whatever.com
   swap save current
   ```

That's it — your accounts are saved.

## Daily use

Run `swap` with no arguments for the interactive picker:

```text
$ swap
Choose an account to swap to:
  1) work            you@company.com                  [saved] (active)
  2) personal        you@example.com                  [saved]
Account # (or name): 2

✓ Auth still valid (you@example.com) — no browser sign-in needed. Restart 'claude'.
```

It lists every account, lets you pick one, and switches. If that account already
has cached credentials (the normal case), the switch is an **instant local
restore** — `claude` starts up already signed into that account with **no
browser and no in-app `/login`**, and you aren't asked anything else.

After restoring, swap checks the session with `claude auth status`. If it's
still valid (or just needs a routine token refresh, which Claude does on launch),
swap says so and stops there. It opens a browser to re-authenticate **only when
the cached session is genuinely expired** — or the first time an account is used.

When a browser sign-in *is* needed, swap uses the browser already saved on that
account and doesn't ask. It only prompts you to pick a browser if the account has
none saved, or its saved browser is no longer installed. The choices offered are
**the browsers your Mac actually registers** — derived at runtime by asking
LaunchServices which top-level apps claim the `http`/`https` URL schemes (the
same set macOS offers as a default browser), with nested helper browsers and
cached copies filtered out.

Then **restart `claude`** — it picks up the swapped account automatically.

### Non-interactive commands

| Command | What it does |
|---------|--------------|
| `swap` | Interactive picker. Empty vault → native `claude auth login` + auto-register. Otherwise: pick account → instant restore, re-auth in browser only if expired |
| `swap add <name> --email <e> [--browser <app>]` | Register an account |
| `swap login <name>` | Browser OAuth, then cache the credential |
| `swap use <name>` | Switch to a cached account (no prompts) |
| `swap save <name>` | Snapshot the current live credential into the vault |
| `swap list` | List configured accounts |
| `swap which` | Show the active account |
| `swap browsers` | List the browsers detected on this Mac |
| `swap remove <name>` | Forget an account |

`--browser` accepts: `Safari`, `Chrome`, `Brave Browser`, `Firefox`, `Arc`, or
`default`.

## Test the flow end to end

The repo ships a hermetic self-test that exercises the whole add → login → save →
swap → use cycle against **stubbed** `claude` and `security` binaries, so it never
touches your real Keychain or credentials:

```bash
./test/e2e.sh
```

It uses a throwaway `SWAP_VAULT` in a temp dir and asserts the vault files,
`.active` marker, and credential round-trip are correct. Expect `ALL TESTS PASSED`.

## How it works

The full mechanism — Keychain service names, OAuth access/refresh tokens, why an
"expired" imported credential still works (refresh tokens), and the
per-config-dir Keychain isolation that lets multiple accounts run *concurrently*
— is documented in the bundled Claude Code skill:

- [`skills/swap/SKILL.md`](skills/swap/SKILL.md)

Copy that folder into `~/.claude/skills/` and Claude Code itself can explain and
drive the tool for you.

## Vault

State lives in `~/.config/swap` (override with `SWAP_VAULT`):

| File | Purpose |
|------|---------|
| `accounts.json` | registry: `name -> { email, browser }` |
| `<name>.keychain` | saved OAuth credential blob (mode 600) |
| `<name>.email` | account email used as the Keychain restore key |
| `.active` | name of the currently restored account |

The `.keychain` files contain live OAuth tokens. The vault is chmod-600 and
**must not** be committed or shared (`.gitignore` already excludes it).

## Scope & limitations

- **macOS only** — depends on `security(1)` and the login Keychain.
- Manages the **default** profile's Keychain item only. Concurrent profiles that
  set a custom `CLAUDE_CONFIG_DIR` use a separate `Claude Code-credentials-<hash>`
  service and are intentionally left untouched — see the skill for that pattern.
- **Over SSH** the login Keychain may be locked; run `security unlock-keychain`
  first, or operate in a local GUI session.

## License

MIT
