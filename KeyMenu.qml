import QtQuick
import qs.Commons
import qs.Ui
import "Pixels.js" as Pixels

// Keybinding menu: pick an action, press Enter, then press the new key.
Dialog {
  id: root

  property var keymap: ({})
  property int index: 0
  property bool learning: false

  signal rebound(string id, string key)
  signal reset()

  title: "Keybindings"

  function move(d) {
    index = Math.max(0, Math.min(Pixels.ACTIONS.length - 1, index + d))
    list.positionViewAtIndex(index, ListView.Contain)
  }

  function handleKey(event) {
    if (learning) {
      if (event.key === Qt.Key_Escape) learning = false
      // shift+1..0 picks colors 11..20 by physical key (xkb 10..19), whatever it types.
      else if (event.modifiers & Qt.ControlModifier || (event.nativeScanCode >= 10 && event.nativeScanCode <= 19)) {}
      else if (Pixels.bindable(event.text)) { learning = false; rebound(Pixels.ACTIONS[index][0], event.text) }
      return true  // swallow everything else (modifiers alone, arrows) while waiting
    }
    if (event.key === Qt.Key_Escape) canceled()
    else if (event.key === Qt.Key_Up || event.text === "k") move(-1)
    else if (event.key === Qt.Key_Down || event.text === "j") move(1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) learning = true
    else if (event.text === "R") reset()
    else return false
    return true
  }

  onOpenedChanged: { index = 0; learning = false }

  Text {
    textFormat: Text.PlainText
    text: root.learning ? "Press the new key for " + Pixels.ACTIONS[root.index][1] + " (esc cancels)"
                        : "Enter: rebind · shift+r: reset all · arrows, ctrl+z/y/c/x/v/s, space, digits are fixed"
    color: Color.popups.text
    opacity: 0.6
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  ListView {
    id: list
    width: Style.space(320)
    height: Math.min(contentHeight, Style.space(320))
    clip: true
    model: Pixels.ACTIONS

    delegate: Button {
      required property int index
      required property var modelData
      width: list.width
      leftAlign: true
      text: modelData[1]
      hasCursor: index === root.index
      onClicked: { root.index = index; root.learning = true }
      onHovered: function(on) { if (on && !root.learning) root.index = index }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.learning && parent.index === root.index ? "…" : Pixels.keyLabel(root.keymap[parent.modelData[0]])
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
