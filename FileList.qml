import QtQuick
import qs.Commons
import qs.Ui

// Load dialog: the PNGs in the save directory, newest first, and a way out to any folder.
Dialog {
  id: root

  property string dir: ""
  property var files: []
  property int index: 0

  signal chosen(string name)
  signal browse()

  title: "Load"

  function move(d) {
    index = Math.max(0, Math.min(files.length - 1, index + d))
    list.positionViewAtIndex(index, ListView.Contain)
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) canceled()
    else if (event.key === Qt.Key_Up || event.text === "k") move(-1)
    else if (event.key === Qt.Key_Down || event.text === "j") move(1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (files.length) chosen(files[index]) }
    else if (event.text === "b") browse()
    else return false
    return true
  }

  onOpenedChanged: if (opened) index = 0

  Text {
    visible: root.files.length === 0
    textFormat: Text.PlainText
    text: "No images in " + root.dir
    color: Color.popups.text
    opacity: 0.6
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  ListView {
    id: list
    visible: root.files.length > 0
    width: Style.space(260)
    height: Math.min(contentHeight, Style.space(280))
    clip: true
    model: root.files

    delegate: Button {
      required property int index
      required property string modelData
      width: list.width
      leftAlign: true
      text: modelData
      hasCursor: index === root.index
      onClicked: root.chosen(modelData)
      onHovered: function(on) { if (on) root.index = index }

      Image {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: parent.height - Style.spacing.sm * 2
        height: width
        fillMode: Image.PreserveAspectFit
        smooth: false
        cache: false
        asynchronous: true
        source: root.opened ? "file://" + root.dir + "/" + encodeURIComponent(modelData) : ""
      }
    }
  }

  Button {
    text: "Browse all folders… (b)"
    bordered: true
    onClicked: root.browse()
  }
}
