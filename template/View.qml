import QtQuick
import qs.Commons

// The whole UI. The bar popup and the hub card both show this, so they can never
// drift apart. Theming comes in through fg/ff/bg; `compact` is for narrow hosts.
Item {
  id: view

  required property var backend
  property color fg: Color.popups.text
  property color bg: Color.popups.background
  property string ff: Style.font.family
  property bool compact: false

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(6)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: view.backend.message
      color: view.fg
      font.family: view.ff
      font.pixelSize: Style.font.subtitle
      wrapMode: Text.Wrap
    }
  }
}
