#!/usr/bin/env bash
# validate-card.sh <plugin-dir> — check that a plugin is a well-formed Omahub card provider.
# Errors exit 1; warnings don't. Does not run or load the plugin.
set -uo pipefail

dir="${1:-}"
[[ -d "$dir" ]] || { echo "usage: $0 <plugin-dir>" >&2; exit 2; }
dir="$(readlink -f "$dir")"   # resolve links so we check the real folder
command -v jq >/dev/null || { echo "needs jq" >&2; exit 2; }

errors=0
err()  { echo "  ✗ $*"; errors=$((errors + 1)); }
warn() { echo "  ! $*"; }
ok()   { echo "  ✓ $*"; }

echo "Checking $(basename "$(readlink -f "$dir")")"
manifest="$dir/manifest.json"
[[ -f "$manifest" ]] || { err "manifest.json missing"; exit 1; }
jq -e . "$manifest" >/dev/null 2>&1 || { err "manifest.json is not valid JSON"; exit 1; }

entry="$(jq -r '.hubCard.entry // empty' "$manifest")"
if [[ -z "$entry" ]]; then
  err "manifest has no hubCard.entry"
else
  if [[ "$entry" =~ ^[A-Za-z0-9_./-]+\.qml$ && "$entry" != *..* && "$entry" != /* ]]; then
    ok "hubCard.entry = $entry"
    if [[ -f "$dir/$entry" ]]; then
      ok "$entry exists"
      [[ -L "$dir/$entry" ]] && err "$entry is a symlink"
      grep -q "implicitHeight" "$dir/$entry" && ok "$entry sets implicitHeight" || err "$entry never sets implicitHeight (the hub sizes the card from it)"
      grep -q "hubWidth" "$dir/$entry" && ok "$entry declares hubWidth" || warn "$entry does not declare hubWidth (optional, but lets the hub pass its width)"
    else
      err "$entry does not exist"
    fi
  else
    err "hubCard.entry must be a safe relative .qml path (got '$entry')"
  fi
fi
contract="$(jq -r '.hubCard.contract // empty' "$manifest")"
if [[ -z "$contract" ]]; then
  warn "no hubCard.contract (assumed 1; set it so future hubs can tell what you built against)"
elif [[ "$contract" =~ ^[0-9]+$ ]] && ((contract >= 1)); then
  ((contract > 1)) && warn "contract $contract is newer than this validator knows (1)" || ok "contract = $contract"
else
  err "hubCard.contract must be a positive integer (got '$contract')"
fi
[[ -n "$(jq -r '.hubCard.title // empty' "$manifest")" ]] && ok "has a card title" || warn "no hubCard.title (the plugin name is used)"

if [[ -n "$(find "$dir" -path "$dir/.git" -prune -o -type l -print -quit)" ]]; then
  err "contains symlinks (the Omarchy marketplace rejects them)"
else
  ok "no symlinks"
fi

# Recommended structure: one View shared by the bar popup and the card.
[[ -f "$dir/View.qml" && -f "$dir/Backend.qml" ]] && ok "Backend.qml + View.qml present" || warn "no Backend.qml/View.qml split (recommended so popup and card cannot drift apart)"
if [[ -f "$dir/BarWidget.qml" ]]; then
  grep -q "View *{" "$dir/BarWidget.qml" && ok "BarWidget hosts the shared View" || warn "BarWidget.qml does not use View"
fi
[[ -f "$dir/HubConfig.qml" ]] && ok "HubConfig.qml present (bar icon can hide when the hub wraps it)" || warn "no HubConfig.qml (the bar icon cannot hide itself when wrapped)"

if command -v omarchy >/dev/null; then
  if omarchy plugin validate "$dir" >/dev/null 2>&1; then ok "omarchy plugin validate passes"; else err "omarchy plugin validate fails"; fi
fi

echo
if ((errors)); then echo "$errors error(s)"; exit 1; fi
echo "Looks good."
