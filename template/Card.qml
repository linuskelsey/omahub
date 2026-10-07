import QtQuick
import qs.Commons

// What the Omahub loads (manifest: hubCard.entry). Contract:
//   - root is an Item with a real implicitHeight
//   - the hub sets hubWidth; the item should fill its parent's width
//   - optional `badge` (int) is added to the bell; optional markViewed() is called on open
//   - optional `property var shell: null` is bound to the bar's shell (for shell-owned services)
//   - optional `property bool hubScrolling: false` is true while the hub is scrolling with the wheel (the hub
//     keeps the wheel then, so a slider under the pointer is not changed by accident)
//   - optional `property bool hubWheelGuard: true`; set to false to opt out of that guard
//   - optional `property bool hubOpen: false` is true only while the panel is open AND this card is expanded
//   - the hub draws the title and chevron; collapsed by default, so do not draw your own title
//   - optional `hubOwnTitle: true`: the view has its own title, so the hub hides its title (keeps a corner chevron) while expanded
Item {
  id: card

  property real hubWidth: 300
  readonly property int badge: data.unread
  function markViewed() { /* e.g. write a "last seen" file */ }

  implicitHeight: view.implicitHeight

  Backend { id: data }

  View {
    id: view
    width: parent.width
    height: implicitHeight
    backend: data
    compact: true
    fg: Color.popups.text
    bg: Color.popups.background
    ff: Style.font.menuFamily
  }
}
