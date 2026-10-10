import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import "Pixels.js" as Pixels

// Scrollable, zoomable view of the image. Every layer is a Canvas with one
// canvas pixel per image pixel, scaled up by `px` without smoothing, so the
// drawing stays DPR-independent and repaints only touch changed pixels.
// Canvas.Image keeps pixels across partial repaints and window remaps, which
// the default double-buffered framebuffer target does not.
Item {
  id: view

  property var img: null
  property int imgW: 1
  property int imgH: 1
  property int px: 1
  property bool grid: false
  property bool greyBg: false
  property int cursorX: 0
  property int cursorY: 0
  property var sel: null        // {x, y, w, h, buf}; buf set while the selection floats
  property var preview: []      // [{x, y}] of a shape in progress
  property string previewColor: "#ffffff"
  property color foreground: Color.foreground
  property color accent: Color.accent

  signal pointerPressed(int x, int y, int button, int modifiers)
  signal pointerMoved(int x, int y, int modifiers, bool pressed)
  signal pointerReleased(int x, int y, int modifiers)
  signal zoomRequested(int direction)

  property var _css: ({})

  function repaintAll() { pix.requestPaint() }

  // Repaint only the bounding box of the points.
  function paintPixels(points) {
    var x0 = imgW, y0 = imgH, x1 = -1, y1 = -1
    for (var i = 0; i < points.length; i++) {
      x0 = Math.min(x0, points[i].x); y0 = Math.min(y0, points[i].y)
      x1 = Math.max(x1, points[i].x); y1 = Math.max(y1, points[i].y)
    }
    if (x1 >= 0) pix.markDirty(Qt.rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
  }

  function css(c) {
    var s = _css[c]
    if (s === undefined) { s = Pixels.toCss(c); _css[c] = s }
    return s
  }

  function clampScroll() {
    flick.contentX = Math.max(0, Math.min(flick.contentX, flick.contentWidth - flick.width))
    flick.contentY = Math.max(0, Math.min(flick.contentY, flick.contentHeight - flick.height))
  }

  function centerOn(x, y) {
    flick.contentX = x * px + px / 2 - flick.width / 2
    flick.contentY = y * px + px / 2 - flick.height / 2
    clampScroll()
  }

  function ensureVisible(x, y) {
    var l = x * px, t = y * px
    if (l < flick.contentX) flick.contentX = l
    else if (l + px > flick.contentX + flick.width) flick.contentX = l + px - flick.width
    if (t < flick.contentY) flick.contentY = t
    else if (t + px > flick.contentY + flick.height) flick.contentY = t + px - flick.height
    clampScroll()
  }

  onPreviewChanged: previewCanvas.requestPaint()
  onPreviewColorChanged: previewCanvas.requestPaint()
  onSelChanged: floatCanvas.requestPaint()

  clip: true

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: Math.max(width, view.imgW * view.px)
    contentHeight: Math.max(height, view.imgH * view.px)
    // Dragging draws; scrolling is the wheel and the scroll bars.
    interactive: false

    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: flick.contentHeight > flick.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff }
    QQC.ScrollBar.horizontal: QQC.ScrollBar { policy: flick.contentWidth > flick.width ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff }

    Item {
      id: content
      x: Math.max(0, (flick.width - width) / 2)
      y: Math.max(0, (flick.height - height) / 2)
      width: view.imgW * view.px
      height: view.imgH * view.px
      clip: true

      Canvas {
        id: checker
        width: view.imgW
        height: view.imgH
        scale: view.px
        transformOrigin: Item.TopLeft
        smooth: false
        renderTarget: Canvas.Image
        property color light: Util.alpha(view.foreground, 0.16)
        property color dark: Util.alpha(view.foreground, 0.06)
        onLightChanged: requestPaint()
        readonly property bool grey: view.greyBg
        onGreyChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          ctx.fillStyle = grey ? "#d0d0d0" : dark
          ctx.fillRect(0, 0, width, height)
          if (grey) return
          ctx.fillStyle = light
          for (var y = 0; y < height; y++)
            for (var x = y & 1; x < width; x += 2) ctx.fillRect(x, y, 1, 1)
        }
      }

      Canvas {
        id: pix
        width: view.imgW
        height: view.imgH
        scale: view.px
        transformOrigin: Item.TopLeft
        smooth: false
        renderTarget: Canvas.Image
        onWidthChanged: view.repaintAll()
        onHeightChanged: view.repaintAll()
        onPaint: function(region) {
          var ctx = getContext("2d"), img = view.img
          if (!img) return
          var x0 = Math.max(0, Math.floor(region.x)), y0 = Math.max(0, Math.floor(region.y))
          var x1 = Math.min(img.w, Math.ceil(region.x + region.width)), y1 = Math.min(img.h, Math.ceil(region.y + region.height))
          ctx.clearRect(x0, y0, x1 - x0, y1 - y0)
          for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++) {
              var c = img.data[y * img.w + x]
              if (c === 0) continue
              ctx.fillStyle = view.css(c)
              ctx.fillRect(x, y, 1, 1)
            }
        }
      }

      Canvas {
        id: previewCanvas
        width: view.imgW
        height: view.imgH
        scale: view.px
        transformOrigin: Item.TopLeft
        smooth: false
        renderTarget: Canvas.Image
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          ctx.fillStyle = view.previewColor
          for (var i = 0; i < view.preview.length; i++) ctx.fillRect(view.preview[i].x, view.preview[i].y, 1, 1)
        }
      }

      Canvas {
        id: floatCanvas
        readonly property var buf: view.sel ? view.sel.buf : null
        visible: !!buf
        x: view.sel ? view.sel.x * view.px : 0
        y: view.sel ? view.sel.y * view.px : 0
        width: buf ? buf.w : 1
        height: buf ? buf.h : 1
        scale: view.px
        transformOrigin: Item.TopLeft
        smooth: false
        renderTarget: Canvas.Image
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          if (!buf) return
          for (var i = 0; i < buf.data.length; i++) {
            if (buf.data[i] === 0) continue
            ctx.fillStyle = view.css(buf.data[i])
            ctx.fillRect(i % buf.w, Math.floor(i / buf.w), 1, 1)
          }
        }
      }

      Rectangle {
        visible: !!view.sel
        x: view.sel ? view.sel.x * view.px : 0
        y: view.sel ? view.sel.y * view.px : 0
        width: view.sel ? view.sel.w * view.px : 0
        height: view.sel ? view.sel.h * view.px : 0
        color: "transparent"
        border.width: 1
        border.color: view.accent

        // Inner line so the outline stays visible on accent-colored pixels.
        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          color: "transparent"
          border.width: 1
          border.color: Color.background
        }
      }

      Rectangle {
        x: view.cursorX * view.px
        y: view.cursorY * view.px
        width: view.px
        height: width
        color: "transparent"
        border.width: 1
        border.color: view.accent
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        // The cell outline is the cursor; a pointer would hide the pixels around it.
        cursorShape: Qt.BlankCursor

        function cellX(m) { return Math.floor(m.x / view.px) }
        function cellY(m) { return Math.floor(m.y / view.px) }

        onPressed: function(m) { view.pointerPressed(cellX(m), cellY(m), m.button, m.modifiers) }
        onPositionChanged: function(m) { view.pointerMoved(cellX(m), cellY(m), m.modifiers, pressed) }
        onReleased: function(m) { view.pointerReleased(cellX(m), cellY(m), m.modifiers) }
        onWheel: function(w) {
          if (w.modifiers & Qt.ControlModifier) {
            view.zoomRequested(w.angleDelta.y > 0 ? 1 : -1)
            return
          }
          var horizontal = (w.modifiers & Qt.ShiftModifier) || w.angleDelta.x !== 0
          if (horizontal) flick.contentX -= (w.angleDelta.x || w.angleDelta.y) / 2
          else flick.contentY -= w.angleDelta.y / 2
          view.clampScroll()
        }
      }
    }
  }

  // Grid lines in viewport coordinates, so its canvas never grows with zoom.
  Canvas {
    id: gridCanvas
    anchors.fill: parent
    visible: view.grid && view.px >= 4
    readonly property var deps: [view.px, view.imgW, view.imgH, flick.contentX, flick.contentY, content.x, content.y, width, height, visible, view.foreground]
    onDepsChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!visible) return
      var ox = content.x - flick.contentX, oy = content.y - flick.contentY
      var x0 = Math.max(0, Math.floor(-ox / view.px)), x1 = Math.min(view.imgW, Math.ceil((width - ox) / view.px))
      var y0 = Math.max(0, Math.floor(-oy / view.px)), y1 = Math.min(view.imgH, Math.ceil((height - oy) / view.px))
      ctx.fillStyle = Util.alpha(view.foreground, 0.25)
      var top = oy + y0 * view.px, bottom = oy + y1 * view.px
      var left = ox + x0 * view.px, right = ox + x1 * view.px
      for (var x = x0; x <= x1; x++) ctx.fillRect(Math.round(ox + x * view.px), top, 1, bottom - top)
      for (var y = y0; y <= y1; y++) ctx.fillRect(left, Math.round(oy + y * view.px), right - left, 1)
    }
  }
}
