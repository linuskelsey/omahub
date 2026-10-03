#!/usr/bin/env bash
# cards.sh — list plugins that declare a notification card in manifest.json:
#   "hubCard": { "entry": "Card.qml", "title": "…" }
# Prints a JSON array of {id, name, title, entry} with absolute entry paths.
set -euo pipefail
shopt -s nullglob
dir="${HOME}/.config/omarchy/plugins"
out=()
for m in "$dir"/*/manifest.json; do
  d="$(dirname "$m")"
  # Omarchy installs a plugin into a folder named after its manifest id. A folder that does not
  # match (a ".bak" copy, a stray checkout) is not the plugin the shell loads: skip it, so the
  # same id is never offered twice.
  [[ "$(basename "$d")" == "$(jq -r '.id // empty' "$m" 2>/dev/null)" ]] || continue
  jq -c --arg d "$d" '
    select(.hubCard.entry? | type == "string")
    | select(.hubCard.entry | test("^[A-Za-z0-9_./-]+\\.qml$") and (contains("..") | not) and (startswith("/") | not))
    | {id, name, title: (.hubCard.title // .name), contract: (.hubCard.contract // 1), entry: ($d + "/" + .hubCard.entry)}
  ' "$m" 2>/dev/null || true
done | jq -sc 'map(select(.entry | test("^/")))'
