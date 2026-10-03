import QtQuick
import Quickshell
import Quickshell.Io

// Non-visual half: owns the data and the actions. One instance lives in the bar
// widget and one in the hub card, so keep it cheap and side-effect free on load.
Item {
  id: root

  property var state: ({})
  readonly property string message: state.message || "Hello from the hub"
  // Optional: a number the hub adds to its bell badge (0 = nothing to see).
  readonly property int unread: state.unread || 0

  // Same as bar.run(): a login shell, detached. Pass untrusted values as argv, never
  // by string-building a shell command.
  function run(command) {
    if (command) Quickshell.execDetached(["bash", "-lc", command])
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/hello-card/state.json"
    watchChanges: true
    printErrors: false
    onLoaded: { try { root.state = JSON.parse(text()) } catch (e) { root.state = ({}) } }
    onFileChanged: reload()
  }
}
