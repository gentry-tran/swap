#!/usr/bin/env bash
# Install swap: symlink the script into ~/.local/bin and migrate any
# pre-existing vault from the legacy ~/.claude/.auth-vault location.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/swap"
BIN="$HOME/.local/bin"
LINK="$BIN/swap"

mkdir -p "$BIN"

# Replace an existing file/symlink so re-running is idempotent.
if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  rm -f "$LINK"
fi
ln -s "$SRC" "$LINK"
chmod +x "$SRC"
echo "Linked $LINK -> $SRC"

# Surface the bundled skill to Claude Code by symlinking it out of the repo
# (the skill's canonical home is THIS repo — never a copy under ~/.claude/skills
# or any skills-warehouse). Idempotent; only links when the skill dir exists.
SKILL_SRC="$(cd "$(dirname "$0")" && pwd)/skills/swap"
if [ -d "$SKILL_SRC" ]; then
  SKILL_LINK="$HOME/.claude/skills/swap"
  mkdir -p "$HOME/.claude/skills"
  if [ -L "$SKILL_LINK" ] || [ -e "$SKILL_LINK" ]; then rm -rf "$SKILL_LINK"; fi
  ln -s "$SKILL_SRC" "$SKILL_LINK"
  echo "Linked $SKILL_LINK -> $SKILL_SRC"
fi

# One-time migration from the legacy vault path, if present and the new one is empty.
NEW_VAULT="${SWAP_VAULT:-${XDG_CONFIG_HOME:-$HOME/.config}/swap}"
OLD_VAULT="$HOME/.claude/.auth-vault"
if [ -f "$OLD_VAULT/accounts.json" ] && [ ! -f "$NEW_VAULT/accounts.json" ]; then
  mkdir -p "$NEW_VAULT"
  cp -p "$OLD_VAULT"/accounts.json "$NEW_VAULT"/ 2>/dev/null || true
  cp -p "$OLD_VAULT"/.active "$NEW_VAULT"/ 2>/dev/null || true
  cp -p "$OLD_VAULT"/*.keychain "$NEW_VAULT"/ 2>/dev/null || true
  cp -p "$OLD_VAULT"/*.oauth.json "$NEW_VAULT"/ 2>/dev/null || true
  cp -p "$OLD_VAULT"/*.email "$NEW_VAULT"/ 2>/dev/null || true
  chmod 700 "$NEW_VAULT"
  echo "Migrated vault: $OLD_VAULT -> $NEW_VAULT"
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "NOTE: add $BIN to your PATH";;
esac
echo "Done. Run: swap"
