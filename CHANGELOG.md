# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/). Versions follow the `version` in `manifest.json`.

## [Unreleased]

### Changed
- The bell shows a tooltip on hover ("Open Omahub", or "Close Omahub" while the panel is open); the button at the end of the panel reads "Omahub settings". The template and migration guide now cover the `tooltipHovered` property the bar requires before it will show a widget's tooltip.

### Fixed
- While the settings overlay is open, global shortcuts no longer reach the window behind it: Omarchy's SUPER+W ("close window") used to close whatever was underneath. The overlay now holds a Wayland shortcuts inhibitor for as long as it is open and treats SUPER+W, and the hub's own shortcuts, as "close settings". No bind or config file is changed or replaced, and everything is released the moment settings close.

## [0.2.2] — 2026-10-03

### Changed
- Renamed to **Omahub**: the repository is now `omahub`, the plugin id `io.github.linuskelsey.omahub`, and the display name "Omahub". The id determines the state folder (`$XDG_STATE_HOME/<id>/`), the IPC target and the layer namespaces, so a plugin's `HubConfig.qml` must read `…/io.github.linuskelsey.omahub/config.json`; the template and [MIGRATING.md](MIGRATING.md) are updated. Nothing had been listed under the earlier ids. Earlier entries below keep the names in use at the time.

## [0.2.1] — 2026-10-03

### Changed
- Renamed the repository to **omarchy-plugin-hub** and the plugin id to `io.github.linuskelsey.omarchy-plugin-hub` (the display name is still "Plugin Hub"). The id determines the state folder (`$XDG_STATE_HOME/<id>/`), the IPC target and the layer namespaces, so a plugin's `HubConfig.qml` must read `…/io.github.linuskelsey.omarchy-plugin-hub/config.json`; the template and [MIGRATING.md](MIGRATING.md) are updated. Nothing had been listed under the old id.

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
- Renamed to **Plugin Hub** (`io.github.linuskelsey.omarchy-plugin-hub`); the manifest key is `hubCard` (was `notificationCard` during development). State lives in `$XDG_STATE_HOME/<id>/`.
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
