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

Make sure `~/.local/bin` is on your `PATH`. Requirements: macOS, `bash`,
`python3`, and Claude Code (`claude`) already installed.

## Set up (one time per account)

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

Which browser for sign-in? (detected on this Mac)
  1) Safari
  2) Google Chrome
  3) Brave Browser
  Enter = keep current (Safari)
Browser #:
Switched to 'personal' (you@example.com). Restart 'claude' to pick up the account.
```

It lists every account, lets you pick one, then asks which browser to use for
sign-in — **only the browsers actually installed on this Mac**, detected at
runtime with `open -Ra`, so the menu never offers a browser you don't have. If
the account already has a cached credential the switch is instant and
browser-independent; the browser only matters when a fresh browser login is
needed.

Then **restart `claude`** to pick up the new account.

### Non-interactive commands

| Command | What it does |
|---------|--------------|
| `swap` | Interactive picker (choose account + browser, switch) |
| `swap add <name> --email <e> [--browser <app>]` | Register an account |
| `swap login <name>` | Browser OAuth, then cache the credential |
| `swap use <name>` | Switch to a cached account (no prompts) |
| `swap save <name>` | Snapshot the current live credential into the vault |
| `swap list` | List configured accounts |
| `swap which` | Show the active account |
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
