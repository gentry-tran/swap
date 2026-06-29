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
