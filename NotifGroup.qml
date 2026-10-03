import QtQuick
import qs.Ui
import qs.Commons

// One app's notifications. Collapsed: newest on top with up to two sheets
// peeking out behind it (macOS-style pile). Expanded: the full list.
Item {
  id: group

  required property var model_
  property bool expanded: false
  property color surface: Color.popups.background
  property color textColor: Color.popups.text
  property var borderSpec: Border.flat(Qt.alpha(Color.accent, 0.5), Math.max(1, Style.space(1)))
  property string fontFamily: Style.font.menuFamily

  signal dismissItem(string stem)
  signal dismissGroup()
  signal activate(var n)

  readonly property var items: model_.items
  readonly property int count: items.length
  readonly property int peeks: expanded ? 0 : Math.min(2, count - 1)
  readonly property real peekStep: Style.space(7)

  width: parent ? parent.width : 0
  height: body.height + peeks * peekStep
  Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  function timeAgo(ms) {
    var s = Math.max(0, Math.floor((Date.now() - ms) / 1000))
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  Repeater {
    model: group.peeks
    delegate: BorderSurface {
      required property int index
      readonly property int depth: group.peeks - index
      x: depth * Style.space(8)
      width: group.width - depth * Style.space(16)
      y: body.height + (group.peeks - depth + 1) * group.peekStep - height
      height: Style.space(20)
      radius: Style.cornerRadius
      color: Qt.darker(group.surface, 1 + depth * 0.12)
      borderSpec: group.borderSpec
      z: -depth
    }
  }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(6)

    Rectangle {
      width: parent.width
      height: group.count > 1 ? Style.space(24) : 0
      visible: group.count > 1
      radius: Style.cornerRadius
      color: group.surface

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: group.model_.app + (group.expanded ? "" : "  ·  " + group.count)
        color: group.textColor
        opacity: 0.75
        font.family: group.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: group.expanded ? "Show less" : "Show all"
        color: Color.accent
        font.family: group.fontFamily
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: group.expanded = !group.expanded
      }
    }

    Repeater {
      model: group.expanded ? group.count : 1
      delegate: BorderSurface {
        id: card
        required property int index
        readonly property var n: group.items[index]
        width: body.width
        height: cardCol.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: group.surface
        borderSpec: group.borderSpec

        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (group.count > 1 && !group.expanded) group.expanded = true
            else group.activate(card.n)
          }
        }

        Row {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(10)

          Item {
            width: Style.space(32); height: Style.space(32)
            Image {
              id: icon
              anchors.fill: parent
              source: card.n && card.n.appIcon ? card.n.appIcon : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              visible: status === Image.Ready
            }
            Rectangle {
              anchors.fill: parent
              visible: !icon.visible
              radius: Style.space(6)
              color: Qt.alpha(Color.accent, 0.25)
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: (group.model_.app || "?").charAt(0).toUpperCase()
                color: group.textColor
                font.family: group.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
            }
          }

          Column {
            id: cardCol
            width: parent.width - Style.space(32) - Style.space(10)
            spacing: Style.space(2)

            Row {
              width: parent.width
              Text {
                width: Math.max(0, parent.width - (hover.containsMouse ? dismiss.implicitWidth : ago.implicitWidth))
                textFormat: Text.PlainText
                text: card.n ? card.n.app : ""
                elide: Text.ElideRight
                color: group.textColor
                opacity: 0.6
                font.family: group.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                id: ago
                textFormat: Text.PlainText
                text: card.n ? group.timeAgo(card.n.timestamp) : ""
                color: group.textColor
                opacity: 0.6
                font.family: group.fontFamily
                font.pixelSize: Style.font.caption
                visible: !hover.containsMouse
              }
              Text {
                id: dismiss
                textFormat: Text.PlainText
                text: ""
                color: Color.accent
                font.family: group.fontFamily
                font.pixelSize: Style.font.body
                visible: hover.containsMouse
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (group.count > 1 && !group.expanded) group.dismissGroup()
                    else group.dismissItem(card.n.stem)
                  }
                }
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: card.n ? card.n.summary : ""
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: group.textColor
              font.family: group.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              visible: text !== ""
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: card.n ? card.n.body : ""
              wrapMode: Text.Wrap
              maximumLineCount: group.expanded ? 6 : 3
              elide: Text.ElideRight
              color: group.textColor
              opacity: 0.85
              font.family: group.fontFamily
              font.pixelSize: Style.font.caption
              visible: text !== ""
            }
          }
        }
      }
    }
  }
}
