import QtQuick
import qs.Commons
import qs.Ui

// Modal card over the editor: scrim, title and a column of content.
Item {
  id: root

  property bool opened: false
  property string title: ""
  // Where keyboard focus goes back to when an inner text field is left.
  property Item returnFocus: null
  default property alias content: body.data

  signal canceled()

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.7)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onClicked: root.canceled()
    }
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(root.width, column.implicitWidth + card.contentLeftInset + card.contentRightInset)
    height: Math.min(root.height, column.implicitHeight + card.contentTopInset + card.contentBottomInset)
    color: Color.popups.background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(14)
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
      id: column
      x: card.contentLeftInset
      y: card.contentTopInset
      spacing: Style.spacing.lg

      Text {
        visible: root.title !== ""
        textFormat: Text.PlainText
        text: root.title
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }

      Column {
        id: body
        spacing: Style.spacing.lg
      }
    }
  }
}
