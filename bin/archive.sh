#!/usr/bin/env bash
# archive.sh <sync|watch|list|remove STEM|clear|seen>
# Keeps a longer notification history than the stock daemon (which trims to
# the newest 10) by copying its history files into a private archive.
# Read-only against the daemon's directories.
set -euo pipefail

SRC="${HOME}/.local/state/omarchy/notifications"
DST="${XDG_STATE_HOME:-$HOME/.local/state}/io.github.linuskelsey.omahub"
MAX_ITEMS=200
MAX_DAYS=30
# retentionDays in the hub's config.json overrides the default (clamped to 1..365).
if [[ -f "$DST/config.json" ]]; then
  days="$(jq -r '.retentionDays // empty' "$DST/config.json" 2>/dev/null || true)"
  [[ "$days" =~ ^[0-9]+$ ]] && ((days >= 1 && days <= 365)) && MAX_DAYS="$days"
fi
STEM_RE='^[0-9]+-[0-9]+$'

for dep in jq inotifywait; do
  command -v "$dep" >/dev/null 2>&1 || { echo "Omahub needs '$dep' (install jq and inotify-tools)." >&2; exit 3; }
done

umask 077
mkdir -p "$DST/items" "$DST/images" "$SRC/history"
touch "$DST/dismissed"

sync_one() {
  local f="$1" stem tmp icon img
  stem="$(basename "$f" .json)"
  [[ "$stem" =~ $STEM_RE ]] || return 0
  [[ -f "$f" && ! -L "$f" ]] || return 0
  # A source older than the retention window is not archived (otherwise the sweep would delete it
  # and the next sync would bring it straight back from the daemon'"'"'s own history).
  [[ -z "$(find "$f" -maxdepth 0 -mtime "+$MAX_DAYS" 2>/dev/null)" ]] || return 0
  # Already archived and the source has not changed since: nothing to do. A rewritten source
  # (the daemon updating a live toast in place) is re-copied.
  [[ -e "$DST/items/$stem.json" && ! "$f" -nt "$DST/items/$stem.json" ]] && return 0
  grep -qxF "$stem" "$DST/dismissed" && return 0

  local filter='.'
  local -a args=()
  for key in appIcon image; do
    local val
    val="$(jq -r --arg k "$key" '.[$k] // ""' "$f")"
    if [[ "$val" == "file://$SRC/images/"* ]]; then
      local base="${val##*/}"
      if [[ "$base" =~ ^[0-9]+-[0-9]+-[A-Za-z]+$ && -f "$SRC/images/$base" && ! -L "$SRC/images/$base" ]]; then
        cp -f "$SRC/images/$base" "$DST/images/$base"
        filter+=" | .$key = \$${key}Url"
        args+=(--arg "${key}Url" "file://$DST/images/$base")
      fi
    fi
  done

  tmp="$(mktemp "$DST/items/.tmp.XXXXXX")"
  if jq -c "${args[@]}" "$filter" "$f" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$DST/items/$stem.json"
  else
    rm -f "$tmp"
  fi
}

trim() {
  find "$DST/items" -name '*.json' -mtime "+$MAX_DAYS" -delete
  { ls -1 "$DST/items" 2>/dev/null | grep -E '\.json$' | sort -r | tail -n "+$((MAX_ITEMS + 1))" || true; } \
    | while read -r name; do rm -f "$DST/items/$name"; done
  for img in "$DST"/images/*; do
    [[ -e "$img" ]] || continue
    local stem
    stem="$(basename "$img")"; stem="${stem%-*}"
    [[ -e "$DST/items/$stem.json" ]] || rm -f "$img"
  done
  tail -n 2000 "$DST/dismissed" > "$DST/dismissed.tmp" && mv -f "$DST/dismissed.tmp" "$DST/dismissed"
}

do_sync() {
  shopt -s nullglob
  # Live toasts (written the moment they appear) first, then history (where they land when they expire).
  for f in "$SRC"/*.json "$SRC"/history/*.json; do sync_one "$f"; done
  trim
}

do_list() {
  local seen=0
  [[ -f "$DST/seen" ]] && seen="$(tr -dc '0-9' < "$DST/seen")"
  : "${seen:=0}"
  shopt -s nullglob
  local files=("$DST"/items/*.json)
  if ((${#files[@]} == 0)); then
    jq -nc --argjson seen "$seen" '{seen:$seen, items:[]}'
  else
    jq -nc --argjson seen "$seen" \
      '{seen:$seen, items:([inputs | .stem = (input_filename | split("/") | last | rtrimstr(".json"))] | sort_by(-.timestamp))}' \
      "${files[@]}"
  fi
}

case "${1:-}" in
  sync) do_sync ;;
  list) do_list ;;
  seen) date +%s%3N > "$DST/seen" ;;
  remove)
    stem="${2:-}"
    [[ "$stem" =~ $STEM_RE ]] || { echo "bad stem" >&2; exit 1; }
    echo "$stem" >> "$DST/dismissed"
    rm -f "$DST/items/$stem.json" "$DST"/images/"$stem"-*
    ;;
  clear)
    shopt -s nullglob
    for f in "$DST"/items/*.json; do basename "$f" .json >> "$DST/dismissed"; done
    rm -f "$DST"/items/*.json "$DST"/images/*
    ;;
  watch)
    trap 'pkill -P $$ 2>/dev/null || true' EXIT
    do_sync || true; echo changed
    while read -r _; do
      sleep 0.15
      do_sync || true; echo changed
    done < <(inotifywait -m -q -e create -e moved_to -e close_write -e delete --format x "$SRC" "$SRC/history")
    ;;
  *) echo "usage: $0 sync|watch|list|remove STEM|clear|seen" >&2; exit 2 ;;
esac
