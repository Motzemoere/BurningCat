import QtQuick
import qs.Commons
import qs.Ui
import "Pixels.js" as Pixels

// Color picker with HSV (square + hue bar), RGB and HSL (channel sliders) modes,
// a hex field and a screen pipette. The color is always held as hue/sat/val.
Dialog {
  id: root

  property real hue: 0
  property real sat: 0
  property real val: 1
  readonly property string hex: Pixels.hsvToHex(hue, sat, val)
  readonly property bool editing: hexField.activeFocus
  readonly property var modes: ["HSV", "RGB", "HSL"]
  property int mode: 0
  property int channel: 0        // slider under the keyboard cursor in RGB / HSL
  readonly property var channels: mode === 1
    ? [{ name: "R", max: 255 }, { name: "G", max: 255 }, { name: "B", max: 255 }]
    : [{ name: "H", max: 359 }, { name: "S", max: 100 }, { name: "L", max: 100 }]

  signal accepted(string hex)
  signal pipetteRequested()

  // Greys have no hue; keep the last one so the hue survives a trip through grey.
  function setHex(h) {
    var c = Pixels.hexToHsv(h)
    if (c.s > 0) hue = c.h
    sat = c.s; val = c.v
  }

  // Slider values in the current mode, in channel units (0..max).
  function values() {
    if (mode === 1) {
      var c = Pixels.parseHex(hex)
      return [(c >>> 16) & 255, (c >>> 8) & 255, c & 255]
    }
    var l = Pixels.hsvToHsl(sat, val)
    return [hue, l.s * 100, l.l * 100]
  }

  // The current color with channel i set to v, as hex (for slider gradients).
  function colorWith(i, v) {
    var vs = values()
    vs[i] = v
    if (mode === 1) return Pixels.toHex((Math.round(vs[0]) << 16) | (Math.round(vs[1]) << 8) | Math.round(vs[2]))
    var c = Pixels.hslToHsv(vs[1] / 100, vs[2] / 100)
    return Pixels.hsvToHex(vs[0], c.s, c.v)
  }

  function setChannel(i, v) {
    v = Math.max(0, Math.min(channels[i].max, v))
    if (mode === 1) { setHex(colorWith(i, v)); return }
    var vs = values()
    vs[i] = v
    var c = Pixels.hslToHsv(vs[1] / 100, vs[2] / 100)
    hue = vs[0]; sat = c.s; val = c.v
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
    }
    if (event.text === "m") { mode = (mode + 1) % modes.length; return true }
    if (mode !== 0) {
      var step = shift ? 10 : 1
      switch (event.key) {
        case Qt.Key_Up: channel = (channel + 2) % 3; return true
        case Qt.Key_Down: channel = (channel + 1) % 3; return true
        case Qt.Key_Left: setChannel(channel, values()[channel] - step); return true
        case Qt.Key_Right: setChannel(channel, values()[channel] + step); return true
      }
    } else switch (event.key) {
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
    spacing: Style.spacing.xs
    Repeater {
      model: root.modes
      Button {
        required property int index
        required property string modelData
        text: modelData
        bordered: true
        selected: root.mode === index
        tooltipText: "Mode (m)"
        onClicked: root.mode = index
      }
    }
  }

  Column {
    visible: root.mode !== 0
    width: hsvRow.width
    height: hsvRow.height
    spacing: Style.spacing.lg

    Repeater {
      model: 3
      Row {
        id: slider
        required property int index
        readonly property var info: root.channels[index]
        spacing: Style.spacing.md

        Text {
          width: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          text: slider.info.name
          color: root.channel === slider.index ? Color.accent : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Item {
          width: hsvRow.width - Style.space(14) - Style.space(32) - 2 * slider.spacing
          height: Style.space(16)

          Rectangle {
            anchors.fill: parent
            border.width: root.channel === slider.index ? 2 : 0
            border.color: Color.accent
            // Seven stops follow the hue wheel; the other channels are near-linear.
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0 / 6; color: root.colorWith(slider.index, slider.info.max * 0 / 6) }
              GradientStop { position: 1 / 6; color: root.colorWith(slider.index, slider.info.max * 1 / 6) }
              GradientStop { position: 2 / 6; color: root.colorWith(slider.index, slider.info.max * 2 / 6) }
              GradientStop { position: 3 / 6; color: root.colorWith(slider.index, slider.info.max * 3 / 6) }
              GradientStop { position: 4 / 6; color: root.colorWith(slider.index, slider.info.max * 4 / 6) }
              GradientStop { position: 5 / 6; color: root.colorWith(slider.index, slider.info.max * 5 / 6) }
              GradientStop { position: 6 / 6; color: root.colorWith(slider.index, slider.info.max * 6 / 6) }
            }
          }
          Rectangle {
            x: root.values()[slider.index] / slider.info.max * parent.width - 1
            width: 3
            height: parent.height
            color: Color.popups.text
          }
          MouseArea {
            anchors.fill: parent
            function pick(m) { root.channel = slider.index; root.setChannel(slider.index, Math.round(m.x / width * slider.info.max)) }
            onPressed: function(m) { pick(m) }
            onPositionChanged: function(m) { pick(m) }
          }
        }

        Text {
          width: Style.space(32)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: Math.round(root.values()[slider.index])
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  Row {
    id: hsvRow
    visible: root.mode === 0
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
