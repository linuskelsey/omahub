# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/). Versions follow the `version` in `manifest.json`.

## [0.2.0] — 2026-10-03

First version intended for publishing. Everything below is relative to the first working prototype.

### Added
- Slide-out panel opened from a bell in the bar, placed in the space the bar leaves free.
- OS notification archive (200 entries, 30 days by default, `retentionDays` configurable) stacked per app, with live toasts captured the moment they appear.
- Click a notification to focus the sending app; an opt-in setting makes a click run the command the sender stored with it (off by default).
- Plugin cards via the optional `hubCard` manifest key and a versioned contract; scrollable frames capped at 400 px.
- Settings: pick and reorder cards (new cards appear unticked, marked "new"), rebind shortcuts, hide wrapped plugins' bar icons, optional desktop blur, delete archived notifications. A "Hub settings" button ends the scrolling panel.
- Shortcuts registered at runtime through `hyprctl eval` (SUPER + N toggles, SUPER + SHIFT + N toggles settings); the shortcut opens the hub on the focused monitor.
- Bell badge: unread-notification count, plus a dot for card-only news.
- The bar's own open-panel mark (via `requestPopout`/`releasePopout`).
- Plugin-author kit: `template/`, `bin/validate-card.sh`, [MIGRATING.md](MIGRATING.md).
- `bin/uninstall.sh` to wipe archived data (plugin removal cannot run code).
- Missing-dependency (`jq`, `inotify-tools`) message in the panel; fallback hint when Hyprland cannot register shortcuts.
- `tests/run.sh` (36 checks for the archiver, card discovery, validator and uninstaller).
- MIT license.

### Changed
- Renamed to **Plugin Hub** (`io.github.linuskelsey.plugin-hub`); the manifest key is `hubCard` (was `notificationCard` during development). State lives in `$XDG_STATE_HOME/<id>/`.
- Blur and every desktop-affecting option are off by default.
- The plugin directory is derived from the component's own location instead of a hardcoded path.

### Fixed
- The template's manifest is now `template/manifest.example.json`: the marketplace treats any `manifest.json` one folder deep as a second plugin and rejects new submissions with more than one.
- Archive watcher died when the archive was empty (`set -e` + `pipefail` in the trim step).
- Expired entries came straight back when the daemon's own history still held their source file.
- Hyprland Lua errors are reported on stdout (exit 7); the hub read only stderr, and swallowed bind failures, so an invalid shortcut showed "ok".
- Teardown on disable/remove, guarded by an ownership token so a reload cannot remove a newer instance's shortcuts.
- Cards and the panel reopened at their previous scroll offset; they now open at the top.
- Several layout bugs (overflowing stack sheets, clipped labels, binding loops, header legibility).

### Tested
Fresh install through `omarchy plugin add … --enable --yes` and removal; two monitors; bar on the top, left and right edges; a light theme (Catppuccin Latte); invalid-shortcut error path. Not tested: a Hyprland using the old (non-Lua) config format.

### Known limitations
- One hub instance (and one archive watcher) per monitor's bar; harmless but redundant.
- If the shell crashes while the hub is open with blur enabled, Hyprland blur stays on until the hub is next opened and closed or Hyprland reloads.
- Urgent notifications are not styled differently; no keyboard navigation beyond Escape (see the [roadmap](ROADMAP.md)).
