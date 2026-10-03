# Migrating a plugin to the Plugin Hub

This guide converts an existing bar-widget plugin so that its popup can also appear as a card in the Plugin Hub, **without changing how it behaves when the hub is absent**. It is based on converting two real plugins (an arXiv scanner and a football tracker). If you are starting a new plugin instead, copy [`template/`](template/) and rename `manifest.example.json` to `manifest.json` (it is named that way here because the marketplace treats any `manifest.json` below the repository root as a second plugin).

You will end up with:

| File | Role |
|------|------|
| `Backend.qml` | non-visual: state files, derived values, actions |
| `View.qml` | the whole popup UI |
| `BarWidget.qml` | bar icon + a popup that hosts `View` (as before, but thinner) |
| `Card.qml` | `Backend` + `View` for the hub |
| `HubConfig.qml` | optional: hides your bar icon when the hub wraps your plugin |

Do it on a branch. Every change is additive, and the check at the end is that the bar popup is unchanged.

## 0. Is your plugin a good fit?

A card works best when the popup is **self-contained UI over state the plugin already owns** (files it reads, commands it runs). Popups that depend on being anchored to the bar, or that need the bar's `focus`/`keyboard` behaviour, will need those parts left in `BarWidget.qml`. A popup that is already a single column about 300–400 px wide ports with almost no changes.

## 1. Sort your `BarWidget.qml` into three piles

Read it top to bottom and mark each piece:

1. **Backend**: properties holding state, `FileView`s, `Process`es, derived `readonly property`s, functions that act (save, refresh, open a link).
2. **View**: everything inside your popup (`KeyboardPanel { … }`), plus any inline `component`s it uses.
3. **Bar-only**: the icon, `MouseArea`, `moduleName`, tooltip, `popupOpen`, `close()`.

## 2. Write `Backend.qml`

```qml
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // …state properties, derived values and FileViews moved here unchanged…

  // The replacement for bar.run(): a login shell, detached.
  function run(command) {
    if (command) Quickshell.execDetached(["bash", "-lc", command])
  }
}
```

- Keep the id `root`; the code you move already says `root.something`.
- Anything that used `root.bar.run(cmd)` becomes `root.run(cmd)` — the card has no bar to call.
- Do not put UI state that only the bar needs (e.g. `popupOpen`) here.
- If you use a property literally named `state`, it will shadow `Item.state`; that worked in the plugins converted so far, but name it something else in new code.

## 3. Write `View.qml`

```qml
import QtQuick
import qs.Ui
import qs.Commons

Item {
  id: view

  required property var backend
  property color fg: Color.popups.text
  property color bg: Color.popups.background
  property string ff: Style.font.family
  property bool compact: false

  implicitHeight: /* height of your content column */

  // …your popup content…
}
```

Move the popup content in, then rewrite references:

| In the old code | In `View.qml` |
|---|---|
| `root.bar.foreground` | `view.fg` |
| `root.bar.background` | `view.bg` |
| `root.bar.fontFamily` | `view.ff` |
| `root.bar.run(` | `backend.run(` |
| `if (root.bar) …` guards | delete (a view always has a backend) |
| any other `root.` | `backend.` |
| `Qt.resolvedUrl("icons/x.svg")` | unchanged (resolves relative to `View.qml`, same folder) |

Two things to watch:

- **Do not anchor the content to the popup.** Top-level children should anchor to `view`/`parent` (they will be inside the card frame or the popup holder), and `implicitHeight` must be real: the hub sizes the card from it.
- **Fixed-height scroll areas are fine** (a `Flickable` with its own height); the card frame scrolls too if the whole card exceeds 400 px.

### Wide layouts: add a `compact` mode

A card is roughly 330 px wide, so a two-column popup must collapse to one column. Replace the `Row` with a `Grid` and key it off `compact`:

```qml
Grid {
  columns: view.compact ? 1 : 3          // left | divider | right
  columnSpacing: Style.space(16)
  rowSpacing: Style.space(16)
  // column widths: view.compact ? parent.width : (parent.width - 2 * spacing - divider) / 2
  // the divider: visible: !view.compact
}
```

Give the divider an explicit height computed from the two columns' `implicitHeight`, not `parent.height` (that creates a layout cycle).

## 4. Slim down `BarWidget.qml`

```qml
BarWidget {
  id: root
  moduleName: "your.plugin.id"            // keep this line!

  Backend { id: data }                    // NOT "backend" — see pitfalls
  HubConfig { id: hub; pluginId: "your.plugin.id" }

  property bool popupOpen: false
  function close() { popupOpen = false }

  visible: !hub.hiddenByHub
  implicitWidth: hub.hiddenByHub ? 0 : row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  // …icon and MouseArea, with root.something → data.something for backend values…

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(popupView.implicitHeight)

    View {
      id: popupView
      anchors.fill: parent
      backend: data
      fg: root.bar ? root.bar.foreground : Color.popups.text
      bg: root.bar ? root.bar.background : Color.popups.background
      ff: root.bar ? root.bar.fontFamily : Style.font.family
    }
  }
}
```

`HubConfig.qml` is copied verbatim from [`template/HubConfig.qml`](template/HubConfig.qml). It is optional; without it your bar icon simply stays visible when the hub wraps you.

## 5. Write `Card.qml`

Copy [`template/Card.qml`](template/Card.qml). The only parts that are yours are the `badge` expression (a number of "things needing attention", or 0) and what `markViewed()` does (e.g. write a "last seen" file, which should clear the badge).

## 6. Declare the card in `manifest.json`

```json
"hubCard": { "entry": "Card.qml", "title": "Your plugin", "contract": 1 }
```

This is an extra top-level key: the shell and the marketplace validator both ignore unknown top-level keys, so the manifest stays valid with or without the hub. Do not add a new value to `kinds`.

## 7. Verify

```bash
bin/validate-card.sh path/to/your-plugin      # from the hub repo
omarchy restart shell                          # the shell does not hot-reload plugins
```

Then **really use it**, because QML errors only appear at load time:

1. Check the shell log for your plugin: `grep -i yourplugin $(ls -t /run/user/$UID/quickshell/by-id/*/log.log | head -1) | grep -iE "warn|error|loop"`.
2. Click your bar icon and compare the popup with the old one. It must look and behave the same.
3. Tick your card in the hub's settings and open the hub. Click through every control; links, buttons and settings forms should all work.
4. Turn on "Hide these cards' own bar icons": your icon should disappear, and come back when you turn it off.

## Pitfalls we hit

- **`backend: backend` is a self-reference.** Inside `View { backend: backend }` the right-hand `backend` resolves to the view's own property. Name the instance `data` (or anything else) in `BarWidget.qml` and `Card.qml`.
- **Keep `moduleName`.** Slicing a file by line numbers can drop it silently; the plugin then loads but the bar cannot find it.
- **Two backends exist when the hub is open** (the bar widget's and the card's). Both watch the same files, so state stays consistent, but a purely local flag such as "scanning…" only changes on the instance you clicked until the next file change. Write to files atomically (write a temp file, then rename) so neither ever reads a half-written file.
- **Binding loops.** A divider whose `height` is `parent.height` while the parent's height depends on the divider will loop; compute from the columns instead.
- **Remove guards, don't invert them.** `if (root.bar)` checks exist because the bar can be absent; in a view the backend is always present.
- **Symlinks are rejected by the marketplace** anywhere inside a plugin folder (the validator checks).
- **Quote shell arguments** with a proper quoting helper, or pass them as an argument vector, when `run()` builds a command from user input.

## Keeping your changes safe

Do the conversion on a branch, keep it non-breaking, and test the bar popup first. If the plugin is published, regenerate the split on a fresh branch off the published `main` rather than rebasing an old one.
