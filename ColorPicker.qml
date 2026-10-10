import QtQuick
import qs.Commons
import qs.Ui
import "Pixels.js" as Pixels

// Hue / saturation-value picker with a hex field and a screen pipette.
Dialog {
  id: root

  property real hue: 0
  property real sat: 0
  property real val: 1
  readonly property string hex: Pixels.hsvToHex(hue, sat, val)
  readonly property bool editing: hexField.activeFocus

  signal accepted(string hex)
  signal pipetteRequested()

  function setHex(h) {
    var c = Pixels.hexToHsv(h)
    hue = c.h; sat = c.s; val = c.v
  }

  function openWith(h, t) {
    setHex(h)
    title = t
  }

  function accept() { accepted(hex) }

  // Returns true when the key was used.
  function handleKey(event) {
    var shift = event.modifiers & Qt.ShiftModifier
    switch (event.key) {
      case Qt.Key_Escape: canceled(); return true
      case Qt.Key_Return:
      case Qt.Key_Enter: accept(); return true
      case Qt.Key_Tab: hexField.forceActiveFocus(); hexField.selectAll(); return true
      case Qt.Key_Left:  if (shift) hue = (hue + 355) % 360; else sat = Math.max(0, sat - 0.05); return true
      case Qt.Key_Right: if (shift) hue = (hue + 5) % 360; else sat = Math.min(1, sat + 0.05); return true
      case Qt.Key_Up:    if (shift) hue = (hue + 5) % 360; else val = Math.min(1, val + 0.05); return true
      case Qt.Key_Down:  if (shift) hue = (hue + 355) % 360; else val = Math.max(0, val - 0.05); return true
    }
    if (event.text === "I" || event.text === "p") { pipetteRequested(); return true }
    return false
  }

  readonly property int side: Style.space(150)

  Row {
    spacing: Style.spacing.lg

    Item {
      width: root.side
      height: root.side

      Rectangle { anchors.fill: parent; color: Pixels.hsvToHex(root.hue, 1, 1) }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "#ffffffff" }
          GradientStop { position: 1; color: "#00ffffff" }
        }
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: "#00000000" }
          GradientStop { position: 1; color: "#ff000000" }
        }
      }
      Rectangle {
        x: root.sat * parent.width - width / 2
        y: (1 - root.val) * parent.height - height / 2
        width: Style.space(10)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.val > 0.5 ? "black" : "white"
      }
      MouseArea {
        anchors.fill: parent
        function pick(m) {
          root.sat = Math.max(0, Math.min(1, m.x / width))
          root.val = Math.max(0, Math.min(1, 1 - m.y / height))
        }
        onPressed: function(m) { pick(m) }
        onPositionChanged: function(m) { pick(m) }
      }
    }

    Item {
      width: Style.space(16)
      height: root.side

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0 / 6; color: "#ff0000" }
          GradientStop { position: 1 / 6; color: "#ffff00" }
          GradientStop { position: 2 / 6; color: "#00ff00" }
          GradientStop { position: 3 / 6; color: "#00ffff" }
          GradientStop { position: 4 / 6; color: "#0000ff" }
          GradientStop { position: 5 / 6; color: "#ff00ff" }
          GradientStop { position: 6 / 6; color: "#ff0000" }
        }
      }
      Rectangle {
        y: root.hue / 360 * parent.height - 1
        width: parent.width
        height: 3
        color: Color.popups.text
      }
      MouseArea {
        anchors.fill: parent
        function pick(m) { root.hue = Math.max(0, Math.min(359.9, m.y / height * 360)) }
        onPressed: function(m) { pick(m) }
        onPositionChanged: function(m) { pick(m) }
      }
    }
  }

  Row {
    spacing: Style.spacing.lg

    Rectangle {
      width: Style.spacing.controlHeight
      height: width
      color: root.hex
      border.width: 1
      border.color: Util.alpha(Color.popups.text, 0.4)
    }

    TextField {
      id: hexField
      width: Style.space(90)
      text: root.hex
      onAccepted: {
        if (Pixels.parseHex(text) >= 0) root.setHex(text)
        root.accept()
      }
      Keys.onEscapePressed: { text = root.hex; root.returnFocus.forceActiveFocus() }
      onActiveFocusChanged: if (!activeFocus && Pixels.parseHex(text) >= 0) root.setHex(text)
    }

    Button {
      iconText: String.fromCodePoint(0xf020a)
      tooltipText: "Pick from screen (shift+i)"
      onClicked: root.pipetteRequested()
    }
  }

  Row {
    spacing: Style.spacing.lg
    Button { text: "Cancel"; bordered: true; onClicked: root.canceled() }
    Button { text: "OK"; bordered: true; selected: true; onClicked: root.accept() }
  }
}
