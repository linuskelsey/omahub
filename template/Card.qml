import QtQuick
import qs.Commons

// What the Plugin Hub loads (manifest: hubCard.entry). Contract:
//   - root is an Item with a real implicitHeight
//   - the hub sets hubWidth; the item should fill its parent's width
//   - optional `badge` (int) is added to the bell; optional markViewed() is called on open
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
