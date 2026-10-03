import QtQuick
import qs.Ui
import qs.Commons

// The normal bar widget. Works with or without the hub: the popup hosts the same View.
BarWidget {
  id: root
  moduleName: "your.org.hello-card"

  Backend { id: data }
  HubConfig { id: hub; pluginId: "your.org.hello-card" }

  property bool popupOpen: false
  function close() { popupOpen = false }

  // Step aside only when the hub wraps this plugin and hides bar icons.
  visible: !hub.hiddenByHub
  implicitWidth: hub.hiddenByHub ? 0 : label.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: "Hello"
    color: root.bar ? root.bar.barForeground : "white"
    font.family: root.bar ? root.bar.fontFamily : "monospace"
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
  }

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
