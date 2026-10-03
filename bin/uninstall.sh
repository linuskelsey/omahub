#!/usr/bin/env bash
# uninstall.sh [--yes] — delete the Omahub's data (config + archived notification text).
#
# `omarchy plugin remove` never runs plugin code, so it leaves ~/.local/state/<id>/ behind.
# Run this first (or afterwards) to wipe it. The hub itself removes its Hyprland shortcuts and
# layer rule when it is unloaded, so there is nothing else to undo.
set -euo pipefail

ID="io.github.linuskelsey.omahub"
DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$ID"

if [[ ! -d "$DIR" ]]; then
  echo "Nothing to delete: $DIR does not exist."
  exit 0
fi

echo "This permanently deletes the Omahub's config and archived notifications:"
echo "  $DIR ($(find "$DIR/items" -name '*.json' 2>/dev/null | wc -l) archived notifications)"
if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 1; }
fi

# Only ever remove the exact directory computed above, and never follow a symlink out of it.
[[ ! -L "$DIR" ]] || { echo "Refusing: $DIR is a symlink." >&2; exit 1; }
rm -rf -- "$DIR"
echo "Deleted $DIR"
