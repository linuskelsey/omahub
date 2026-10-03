import QtQuick
import Quickshell
import Quickshell.Io

// Optional. Lets the bar icon step aside when the user has set the Notification
// Hub to wrap this plugin and hide bar icons. Without a hub config this is a no-op.
Item {
  id: root

  property string pluginId: ""
  property var cfg: ({})
  readonly property bool hiddenByHub: cfg.hideBarWidgets === true && (cfg.cards || []).indexOf(pluginId) >= 0

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/io.github.linuskelsey.plugin-hub/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: { try { root.cfg = JSON.parse(text()) } catch (e) { root.cfg = ({}) } }
    onFileChanged: reload()
  }
}
