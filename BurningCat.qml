import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Pixels.js" as Pixels
import "Png.js" as Png

// Panel plugin that shows the pixel editor in a normal (tiled) Hyprland
// window. Drawing logic lives in Pixels.js / Png.js; this file holds editor
// state, input and file I/O.
Item {
  id: root

  property var shell: null       // host injection
  property bool opened: false
  property bool closingFromHost: false

  function open(payloadJson) {
    opened = true
    window.visible = true
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  // Host-initiated close (`shell hide`); the host already knows.
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
    opened = false
  }

  // User-initiated close (q, esc, killactive): tell the host so toggle stays in sync.
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("motzemoere.burningcat")
    else close()
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string dir: home + "/Pictures/BurningCat"

  // ------------------------------------------------------------ editor state
  property var img: Pixels.create(32, 32)
  property int imgW: 32
  property int imgH: 32
  property var history: new Pixels.History()
  property var colors: Pixels.mergePalette([], [], Pixels.PALETTE_SIZE).concat(Pixels.EXTRA_COLORS)  // palette, then the extra slots
  property int slot: 0
  property string current: "#ffffff"
  property string tool: "pixel"
  property int penSize: 1        // pen and eraser block side, one of Pixels.PEN_SIZES
  property bool grid: false
  property string bg: ""         // one of Pixels.BACKGROUNDS
  property bool bgMenu: false    // background swatches shown in place of the tool options
  property int px: fitPx
  property int cursorX: 0
  property int cursorY: 0
  property var startPt: null     // first corner of a shape or selection in progress
  property var sel: null         // {x, y, w, h, buf}; buf is set while it floats
  property var preview: []
  property var drag: null        // mouse gesture in progress
  property string fileName: ""   // the editable field, without .png
  property string currentFile: "" // file this image was loaded from / saved to
  property int rev: 0            // bumped on every edit
  property int savedRev: 0
  property int docId: 0          // bumped on new/load so late I/O callbacks can tell
  property var files: []
  property string dialog: ""
  property string note: ""
  property var pendingConfirm: null
  property string pipetteTarget: ""
  property string pickerMode: ""
  property bool savingAs: false  // the filename field was focused by save as; enter saves
  property var keymap: Pixels.defaultBindings()
  property bool snapshotPending: false  // the gesture's first real change takes the undo snapshot

  // The Reference: a read-only image shown beside the Image.
  property var refImg: null
  property string refFile: ""
  property int refPx: 1
  property int refCursorX: 0
  property int refCursorY: 0
  property var refStartPt: null
  property var refSel: null      // {x, y, w, h, buf: null}; never floats
  property bool onRef: false     // keys go to the Reference
  property bool pickingRef: false // the file list opens a Reference

  readonly property bool textEditing: fileField.activeFocus || picker.editing || widthField.activeFocus || heightField.activeFocus

  readonly property var tools: [
    { id: "pixel", icon: 0xf03eb, label: "Pixel" },
    { id: "eyedropper", icon: 0xf020a, label: "Eyedropper" },
    { id: "select", icon: 0xf0489, label: "Select" },
    { id: "fill", icon: 0xf0266, label: "Color pot" },
    { id: "line", icon: 0xf055e, label: "Line" },
    { id: "rectangle", icon: 0xf0763, label: "Rectangle" },
    { id: "circle", icon: 0xf0766, label: "Circle" },
    { id: "triangle", icon: 0xf0537, label: "Triangle" },
    { id: "hexagon", icon: 0xf02d9, label: "Hexagon" },
    { id: "octagon", icon: 0xf03c4, label: "Octagon" },
  ]
  readonly property var shapeTools: ["line", "rectangle", "circle", "triangle", "hexagon", "octagon"]
  readonly property real slotSize: Style.space(22)  // color slots and tool option buttons
  readonly property var zoomSteps: [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]

  function keyOf(id) { return Pixels.keyLabel(keymap[id]) }

  function toolLabel(id) {
    for (var i = 0; i < tools.length; i++) if (tools[i].id === id) return tools[i].label
    return id
  }

  // ------------------------------------------------------------ view sizing
  // The canvas fills whatever the window is tiled to.
  readonly property int chromeH: bottomRow.implicitHeight + fileField.implicitHeight + statusRow.implicitHeight + layout.spacing * 3
  readonly property int viewW: Math.max(64, window.width - 2 * layout.anchors.margins - sidebar.implicitWidth - topRow.spacing)
  readonly property int viewH: Math.max(64, window.height - 2 * layout.anchors.margins - chromeH)
  readonly property int paneW: refImg ? Math.max(32, Math.floor((viewW - topRow.spacing) / 2)) : viewW
  readonly property int fitPx: Math.max(1, Math.floor(Math.min(paneW / imgW, viewH / imgH)))
  readonly property int refFitPx: refImg ? Math.max(1, Math.floor(Math.min(paneW / refImg.w, viewH / refImg.h))) : 1

  function zoomStep(cur, fit, direction) {
    var steps = zoomSteps.concat([fit]).sort(function(a, b) { return a - b })
    if (direction > 0) { for (var i = 0; i < steps.length; i++) if (steps[i] > cur) return steps[i] }
    else { for (var j = steps.length - 1; j >= 0; j--) if (steps[j] < cur) return steps[j] }
    return cur
  }

  function zoom(direction) {
    if (onRef) {
      refPx = zoomStep(refPx, refFitPx, direction)
      Qt.callLater(function() { refView.centerOn(root.refCursorX, root.refCursorY) })
      return
    }
    px = zoomStep(px, fitPx, direction)
    Qt.callLater(function() { view.centerOn(root.cursorX, root.cursorY) })
  }

  // ------------------------------------------------------------ messages
  function say(text) { note = text; noteTimer.restart() }

  Timer { id: noteTimer; interval: 4000; onTriggered: root.note = "" }

  // ------------------------------------------------------------ image edits
  function setImage(next) {
    var resized = next.w !== imgW || next.h !== imgH
    img = next
    imgW = next.w
    imgH = next.h
    cursorX = Math.min(cursorX, imgW - 1)
    cursorY = Math.min(cursorY, imgH - 1)
    if (resized) px = fitPx
    view.repaintAll()
  }

  function pushHistory() { history.push(img); rev++ }

  function drawPoints(points, c) {
    var changed = points.filter(function(p) { return Pixels.inside(img, p.x, p.y) && Pixels.get(img, p.x, p.y) !== c })
    if (!changed.length) return
    if (snapshotPending) { pushHistory(); snapshotPending = false }
    changed.forEach(function(p) { Pixels.set(img, p.x, p.y, c) })
    view.paintPixels(changed)
    rev++
  }

  function currentInt() { return Pixels.parseHex(current) }

  function setCursor(x, y) {
    cursorX = Math.max(0, Math.min(imgW - 1, x))
    cursorY = Math.max(0, Math.min(imgH - 1, y))
  }

  function moveCursor(dx, dy) {
    setCursor(cursorX + dx, cursorY + dy)
    view.ensureVisible(cursorX, cursorY)
    if (startPt) updatePreview(startPt, { x: cursorX, y: cursorY }, false)
  }

  function pick(x, y, from) {
    var c = Pixels.get(from || img, x, y)
    if ((c >>> 24) === 0) { say("Transparent pixel"); return }
    current = Pixels.toHex(c)
    slot = colors.indexOf(current)
  }

  function selectSlot(i) {
    slot = i
    if (colors[i]) current = colors[i]
  }

  function setTool(id) {
    commitSelection()
    cancelShape()
    bgMenu = false
    tool = id
  }

  function setBg(c) {
    bg = c
    bgMenu = false
    writeState()
  }

  function isShape(t) { return shapeTools.indexOf(t) >= 0 }

  function updatePreview(a, b, keepRatio) {
    if (tool === "select") { sel = rectSel(a, b); return }
    preview = Pixels.shape(tool, a.x, a.y, b.x, b.y, keepRatio)
  }

  function commitShape(a, b, keepRatio) {
    snapshotPending = true
    drawPoints(Pixels.shape(tool, a.x, a.y, b.x, b.y, keepRatio), currentInt())
    cancelShape()
  }

  function cancelShape() {
    startPt = null
    preview = []
  }

  function fillAt(x, y, c) {
    commitSelection()
    if (!Pixels.inside(img, x, y) || Pixels.get(img, x, y) === c) return
    pushHistory()
    Pixels.fill(img, x, y, c)
    view.repaintAll()
  }

  // ------------------------------------------------------------ selection
  function rectSel(a, b, from) {
    var r = Pixels.clipRect(from || img, Pixels.normRect(a.x, a.y, b.x, b.y))
    return r ? { x: r.x, y: r.y, w: r.w, h: r.h, buf: null } : null
  }

  function inSel(x, y) { return sel && x >= sel.x && y >= sel.y && x < sel.x + sel.w && y < sel.y + sel.h }

  // Cut the selected pixels out so they float above the image.
  function lift() {
    if (!sel || sel.buf) return
    pushHistory()
    var buf = Pixels.extract(img, sel)
    Pixels.clear(img, sel)
    view.repaintAll()
    sel = { x: sel.x, y: sel.y, w: sel.w, h: sel.h, buf: buf }
  }

  function commitSelection() {
    if (sel && sel.buf) {
      Pixels.blit(img, sel.buf, sel.x, sel.y)
      view.repaintAll()
      rev++
    }
    sel = null
  }

  function moveSel(dx, dy) {
    if (!sel) return
    lift()
    sel = { x: sel.x + dx, y: sel.y + dy, w: sel.w, h: sel.h, buf: sel.buf }
  }

  function transformSel(fn) {
    if (!sel) return
    lift()
    var b = fn(sel.buf)
    sel = { x: sel.x, y: sel.y, w: b.w, h: b.h, buf: b }
  }

  function deleteSel() {
    if (!sel) return
    if (!sel.buf) {
      pushHistory()
      Pixels.clear(img, sel)
      view.repaintAll()
    }
    sel = null
  }

  function copySel() {
    var s = onRef ? refSel : sel
    if (!s) { say("Nothing selected"); return false }
    var b = s.buf || Pixels.extract(onRef ? refImg : img, s)
    runJob(["sh", "-c", "base64 -d | wl-copy -t image/png >/dev/null 2>&1"], Png.base64Encode(Png.encode(b)), function(ok) {
      root.say(ok ? "Copied " + b.w + "x" + b.h : "Copy failed (is wl-clipboard installed?)")
    })
    return true
  }

  function cutSel() { if (copySel()) deleteSel() }

  function paste() {
    var doc = docId
    runJob(["sh", "-c", "wl-paste -n -t image/png 2>/dev/null | base64 -w0"], "", function(ok, out) {
      if (doc !== root.docId) return
      var bytes = Png.base64Decode(out)
      if (!bytes.length) { root.say("No image on the clipboard"); return }
      var buf
      try { buf = Png.decode(bytes, Pixels.MAX_SIDE) } catch (e) { root.say(e.message); return }
      root.commitSelection()
      root.cancelShape()
      root.pushHistory()
      root.tool = "select"
      root.sel = { x: Math.max(0, Math.min(root.cursorX, root.imgW - buf.w)), y: Math.max(0, Math.min(root.cursorY, root.imgH - buf.h)),
                   w: buf.w, h: buf.h, buf: buf }
    })
  }

  // ------------------------------------------------------------ reference
  function openReferenceFiles() {
    pickingRef = true
    refreshFiles()
    dialog = "files"
  }

  // name is relative to dir. A failed restore forgets the Reference quietly.
  function openReference(name, restoring) {
    closeDialog()
    var fail = function(message) {
      if (!restoring) { root.say(message); return }
      root.refFile = ""
      root.writeState()
    }
    runJob(["base64", "-w0", dir + "/" + name], "", function(ok, out) {
      if (!ok) { fail("Could not read " + name); return }
      var dec
      try { dec = Png.decode(Png.base64Decode(out), Pixels.MAX_SIDE) } catch (e) { fail(e.message); return }
      root.refImg = dec
      root.refFile = name
      root.refSel = null
      root.refStartPt = null
      root.refCursorX = 0
      root.refCursorY = 0
      root.px = root.fitPx
      root.refPx = root.refFitPx
      refView.repaintAll()
      root.writeState()
      if (!restoring) root.say("Reference " + name)
    })
  }

  function closeReference() {
    refImg = null
    refFile = ""
    refSel = null
    refStartPt = null
    onRef = false
    px = fitPx
    writeState()
  }

  function switchSide() {
    if (!refImg) return
    cancelShape()
    refStartPt = null
    onRef = !onRef
  }

  function setRefCursor(x, y) {
    refCursorX = Math.max(0, Math.min(refImg.w - 1, x))
    refCursorY = Math.max(0, Math.min(refImg.h - 1, y))
    if (refStartPt) refSel = rectSel(refStartPt, { x: refCursorX, y: refCursorY }, refImg)
  }

  function onRefPressed(x, y, button, mods) {
    keys.forceActiveFocus()
    if (!onRef) switchSide()
    setRefCursor(x, y)
    if (tool === "eyedropper" || (mods & Qt.AltModifier)) { pick(refCursorX, refCursorY, refImg); return }
    refStartPt = { x: refCursorX, y: refCursorY }
    refSel = rectSel(refStartPt, refStartPt, refImg)
  }

  function onRefMoved(x, y, mods, pressed) {
    if (pressed || (x >= 0 && y >= 0 && x < refImg.w && y < refImg.h)) setRefCursor(x, y)
  }

  // Keys that act differently on the Reference; the rest fall through to the Image.
  function refKey(event) {
    var ctrl = event.modifiers & Qt.ControlModifier, k = event.key
    var dx = k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : 0
    var dy = k === Qt.Key_Up ? -1 : k === Qt.Key_Down ? 1 : 0
    if (dx || dy) {
      if (ctrl) refView.scrollBy(dx, dy)
      setRefCursor(refCursorX + dx, refCursorY + dy)
      refView.ensureVisible(refCursorX, refCursorY)
      return true
    }
    if (k === Qt.Key_Space) {
      var p = { x: refCursorX, y: refCursorY }
      if (tool === "eyedropper") pick(p.x, p.y, refImg)
      else if (refStartPt) refStartPt = null
      else { refStartPt = p; refSel = rectSel(p, p, refImg) }
      return true
    }
    if (k === Qt.Key_Escape) {
      if (bgMenu) bgMenu = false
      else if (refStartPt || refSel) { refStartPt = null; refSel = null }
      else requestClose()
      return true
    }
    var edits = ["erase", "flipH", "flipV", "rotateCw", "rotateCcw"]
    if (ctrl ? k === Qt.Key_X || k === Qt.Key_V
             : k === Qt.Key_Delete || k === Qt.Key_Backspace || edits.indexOf(Pixels.actionFor(keymap, event.text)) >= 0) {
      say("Reference is read-only")
      return true
    }
    return false
  }

  // ------------------------------------------------------------ history
  function undo() {
    commitSelection()
    cancelShape()
    var prev = history.back(img)
    if (prev) { setImage(prev); rev++ } else say("Nothing to undo")
  }

  function redo() {
    commitSelection()
    cancelShape()
    var next = history.forward(img)
    if (next) { setImage(next); rev++ } else say("Nothing to redo")
  }

  function resizeCanvas(w, h) {
    commitSelection()
    cancelShape()
    if (w === imgW && h === imgH) return
    pushHistory()
    setImage(Pixels.resize(img, w, h))
  }

  readonly property var upscaleFactors: [2, 3, 4]
  property int upscaleIndex: 0

  function upscale(k) {
    closeDialog()
    if (Math.max(imgW, imgH) * k > Pixels.MAX_SIDE) { say("Too big: max " + Pixels.MAX_SIDE + "x" + Pixels.MAX_SIDE); return }
    commitSelection()
    cancelShape()
    pushHistory()
    setImage(Pixels.scale(img, k))
  }

  function upscaleKey(event) {
    if (event.key === Qt.Key_Escape) closeDialog()
    else if (event.key === Qt.Key_Left || event.text === "h") upscaleIndex = Math.max(0, upscaleIndex - 1)
    else if (event.key === Qt.Key_Right || event.text === "l") upscaleIndex = Math.min(upscaleFactors.length - 1, upscaleIndex + 1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) upscale(upscaleFactors[upscaleIndex])
    else if (upscaleFactors.indexOf(Number(event.text)) >= 0) upscale(Number(event.text))
    else return false
    return true
  }

  // ------------------------------------------------------------ input
  function activate(keepRatio) {
    var p = { x: cursorX, y: cursorY }
    if (tool === "pixel") { commitSelection(); snapshotPending = true; drawPoints(Pixels.stamp([p], penSize), currentInt()) }
    else if (tool === "eyedropper") pick(p.x, p.y)
    else if (tool === "fill") fillAt(p.x, p.y, currentInt())
    else if (!startPt) {
      if (tool === "select") commitSelection()
      startPt = p
      updatePreview(p, p, keepRatio)
    } else {
      if (tool === "select") sel = rectSel(startPt, p)
      else commitShape(startPt, p, keepRatio)
      startPt = null
    }
  }

  function cancel() {
    if (startPt) { cancelShape(); if (tool === "select") sel = null }
    else if (sel) commitSelection()
    else root.requestClose()
  }

  function onPointerPressed(x, y, button, mods) {
    keys.forceActiveFocus()
    if (onRef) switchSide()
    setCursor(x, y)
    var erase = button === Qt.RightButton
    if (mods & Qt.AltModifier) { pick(x, y); return }
    drag = { last: { x: x, y: y }, move: false }
    if (tool === "pixel") { commitSelection(); snapshotPending = true; drawPoints(Pixels.stamp([{ x: x, y: y }], penSize), erase ? 0 : currentInt()); drag.erase = erase }
    else if (tool === "eyedropper") pick(x, y)
    else if (tool === "fill") fillAt(x, y, erase ? 0 : currentInt())
    else if (tool === "select" && inSel(x, y)) { lift(); drag.move = true }
    else {
      commitSelection()
      startPt = { x: x, y: y }
      updatePreview(startPt, startPt, mods & Qt.ControlModifier)
    }
  }

  function onPointerMoved(x, y, mods, pressed) {
    if (!pressed || !drag) {
      if (x >= 0 && y >= 0 && x < imgW && y < imgH) setCursor(x, y)
      if (startPt && !drag) updatePreview(startPt, { x: cursorX, y: cursorY }, false)
      return
    }
    var p = { x: x, y: y }
    if (tool === "pixel") drawPoints(Pixels.stamp(Pixels.line(drag.last.x, drag.last.y, x, y), penSize), drag.erase ? 0 : currentInt())
    else if (drag.move) moveSel(x - drag.last.x, y - drag.last.y)
    else if (startPt) updatePreview(startPt, { x: Math.max(0, Math.min(imgW - 1, x)), y: Math.max(0, Math.min(imgH - 1, y)) }, mods & Qt.ControlModifier)
    drag.last = p
    setCursor(x, y)
  }

  function onPointerReleased(x, y, mods) {
    var p = { x: Math.max(0, Math.min(imgW - 1, x)), y: Math.max(0, Math.min(imgH - 1, y)) }  // same clamp as the preview
    if (drag && startPt && isShape(tool)) commitShape(startPt, p, mods & Qt.ControlModifier)
    else if (drag && startPt) startPt = null
    drag = null
  }

  function handleKey(event) {
    if (dialog === "picker") return picker.handleKey(event)
    if (dialog === "files") return fileList.handleKey(event)
    if (dialog === "confirm") return confirm.handleKey(event)
    if (dialog === "export") return exportKey(event)
    if (dialog === "upscale") return upscaleKey(event)
    if (dialog === "keys") return keyMenu.handleKey(event)
    if (dialog !== "") {
      if (event.key === Qt.Key_Escape) { closeDialog(); return true }
      return false
    }
    if (onRef && refKey(event)) return true

    var ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
    var k = event.key
    if (ctrl) {
      if (k === Qt.Key_Z) { shift ? redo() : undo(); return true }
      if (k === Qt.Key_Y) { redo(); return true }
      if (k === Qt.Key_C) { copySel(); return true }
      if (k === Qt.Key_X) { cutSel(); return true }
      if (k === Qt.Key_V) { paste(); return true }
      if (k === Qt.Key_S) { saveAs(); return true }
    }

    var dx = k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : 0
    var dy = k === Qt.Key_Up ? -1 : k === Qt.Key_Down ? 1 : 0
    if (dx || dy) {
      if (shift && sel) moveSel(dx, dy)
      else if (ctrl) { view.scrollBy(dx, dy); moveCursor(dx, dy) }  // the image slides under a still cursor
      else moveCursor(dx, dy)
      return true
    }
    if (k === Qt.Key_Space) { activate(ctrl); return true }
    if (k === Qt.Key_Delete || k === Qt.Key_Backspace) { erase(); return true }
    if (k === Qt.Key_Escape) { if (bgMenu) bgMenu = false; else cancel(); return true }
    if (ctrl) return false

    var t = event.text
    // shift+1..0 by physical key, since the shifted characters differ per layout;
    // xkb keycodes 10..19 are that row, which maps straight onto slots 11..20.
    if (shift && event.nativeScanCode >= 10 && event.nativeScanCode <= 19) { selectSlot(event.nativeScanCode); return true }
    if (t >= "0" && t <= "9" && t.length === 1) { selectSlot((Number(t) + 9) % 10); return true }
    var action = Pixels.actionFor(keymap, t)
    if (action) { runAction(action); return true }
    // shift+<pen key> cycles the size backwards when that shifted key is unbound.
    if (tool === "pixel" && t !== t.toLowerCase() && Pixels.actionFor(keymap, t.toLowerCase()) === "pixel") { cyclePenSize(-1); return true }
    if (t === "=" && keymap.zoomIn === "+") { zoom(1); return true }  // unshifted + on US layouts
    return false
  }

  function erase() {
    if (sel) deleteSel()
    else if (tool === "fill") fillAt(cursorX, cursorY, 0)
    else { commitSelection(); snapshotPending = true; drawPoints(Pixels.stamp([{ x: cursorX, y: cursorY }], penSize), 0) }
  }

  function cyclePenSize(d) {
    var n = Pixels.PEN_SIZES.length
    penSize = Pixels.PEN_SIZES[(Pixels.PEN_SIZES.indexOf(penSize) + d + n) % n]
  }

  function runAction(id) {
    if (id === "pixel" && tool === "pixel") { cyclePenSize(1); return }
    for (var i = 0; i < tools.length; i++) if (tools[i].id === id) { setTool(id); return }
    switch (id) {
      case "erase": erase(); break
      case "slot21": selectSlot(20); break
      case "slot22": selectSlot(21); break
      case "flipH": transformSel(Pixels.flipH); break
      case "flipV": transformSel(Pixels.flipV); break
      case "rotateCw": transformSel(function(b) { return Pixels.rotate(b, true) }); break
      case "rotateCcw": transformSel(function(b) { return Pixels.rotate(b, false) }); break
      case "addColor": openPicker("add"); break
      case "pipette": startPipette("add"); break
      case "grid": grid = !grid; break
      case "background":
        if (bgMenu) { var i = Pixels.BACKGROUNDS.indexOf(bg); bg = Pixels.BACKGROUNDS[(i + 1) % Pixels.BACKGROUNDS.length]; writeState() }
        else bgMenu = true
        break
      case "zoomIn": zoom(1); break
      case "zoomOut": zoom(-1); break
      case "new": newImage(); break
      case "save": save(); break
      case "load": openFiles(); break
      case "export": dialog = "export"; break
      case "upscale": dialog = "upscale"; break
      case "reference": refImg ? closeReference() : openReferenceFiles(); break
      case "switchSide": switchSide(); break
      case "keys": dialog = "keys"; break
      case "quit": root.requestClose(); break
    }
  }

  function rebindKey(id, key) {
    var next = Object.assign({}, keymap), other = Pixels.rebind(next, id, key)
    keymap = next
    writeState()
    if (other) say(Pixels.ACTIONS.filter(function(a) { return a[0] === other })[0][1] + " moved to " + keyOf(other))
  }

  // ------------------------------------------------------------ palette
  function themeColors() {
    themeFile.reload()
    return Pixels.themePalette(themeFile.text(), [String(Color.foreground), String(Color.background),
      String(Color.accent), String(Color.urgent), String(Color.muted)])
  }

  function setColors(next) {
    colors = next
    writeState()
  }

  // Replace the palette part, keeping the extra slots.
  function setPalette(palette) { setColors(palette.concat(colors.slice(Pixels.PALETTE_SIZE))) }

  function addColor(hex) {
    var next = colors.slice(), i = next.indexOf("")
    if (i < 0) i = Math.max(0, slot)
    next[i] = hex
    setColors(next)
    selectSlot(i)
  }

  function openPicker(mode) {
    pickerMode = mode
    picker.openWith(mode === "replace" && colors[slot] ? colors[slot] : current,
                    mode === "replace" ? "Replace color " + (slot + 1) : "New color")
    dialog = "picker"
  }

  function pickerAccepted(hex) {
    closeDialog()
    if (pickerMode === "replace") {
      var next = colors.slice()
      next[slot] = hex
      setColors(next)
      selectSlot(slot)
    } else addColor(hex)
  }

  function startPipette(target) {
    pipetteTarget = target
    pipette.running = true
  }

  Process {
    id: pipette
    command: ["sh", "-c", "hyprpicker -f hex -l -q 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        var m = /#[0-9a-f]{6}/.exec(text)
        if (!m) root.say("Pipette canceled")
        else if (root.pipetteTarget === "picker") picker.setHex(m[0])
        else root.addColor(m[0])
      }
    }
  }

  // ------------------------------------------------------------ files
  function closeDialog() {
    dialog = ""
    keys.forceActiveFocus()
  }

  function ask(message, action) {
    confirm.message = message
    confirm.selectedIndex = 1
    pendingConfirm = action
    dialog = "confirm"
  }

  function writeCmd(path) {
    return ["sh", "-c", 'mkdir -p "$(dirname "$1")" && base64 -d > "$1.tmp" && mv -f "$1.tmp" "$1"', "sh", path]
  }

  function writeBytes(name, bytes, done) {
    runJob(writeCmd(dir + "/" + name), Png.base64Encode(bytes), function(ok) {
      if (!ok) root.say("Could not save " + name)
      else root.refreshFiles()
      done(ok)
    })
  }

  function exists(name, done) { runJob(["test", "-e", dir + "/" + name], "", function(ok) { done(ok) }) }

  // Save `bytes` (encoded at revision r) as the current document's file.
  // done(ok) is optional.
  function writeImage(name, bytes, r, quiet, done) {
    var doc = docId
    writeBytes(name, bytes, function(ok) {
      if (ok && !quiet) root.say("Saved " + name)
      if (ok && doc === root.docId) {
        root.currentFile = name
        root.fileName = name.replace(/\.png$/, "")
        root.savedRev = r
        root.writeState()
      }
      if (done) done(ok)
    })
  }

  function save() {
    commitSelection()
    var typed = fileName.trim()
    var name = typed ? Pixels.cleanName(typed) : Pixels.timestampName(new Date())
    if (!name) { say("Invalid filename"); return }
    var bytes = Png.encode(img), r = rev
    if (name === currentFile) { writeImage(name, bytes, r, false); return }
    exists(name, function(yes) {
      if (!yes) root.writeImage(name, bytes, r, false)
      else root.ask("Overwrite " + name + "?", function() { root.writeImage(name, bytes, r, false) })
    })
  }

  function saveAs() {
    savingAs = true
    fileField.forceActiveFocus()
    fileField.selectAll()
    say("Type a name, enter saves, esc cancels")
  }

  // Never asks. done(ok), optional, runs once the image is on disk or
  // nothing needed saving.
  function autosave(done) {
    done = done || function() {}
    commitSelection()
    if (rev === savedRev || Pixels.isEmpty(img)) { done(true); return }
    var bytes = Png.encode(img), r = rev, cur = currentFile
    var typed = Pixels.cleanName(fileName), stamp = Pixels.timestampName(new Date())
    var write = function(yes) { root.writeImage(Pixels.autosaveName(typed, cur, yes, stamp), bytes, r, true, done) }
    if (typed && typed !== cur) exists(typed, write)
    else write(false)
  }

  // Saves edits that would otherwise only reach disk on close, so a shell
  // restart or crash loses at most this interval.
  Timer {
    id: autosaveTimer
    interval: 30000
    onTriggered: if (root.drag || root.sel) restart(); else root.autosave()
  }
  onRevChanged: autosaveTimer.restart()

  function resetDocument(next) {
    docId++
    history = new Pixels.History()
    sel = null
    cancelShape()
    setImage(next)
    rev++
    savedRev = rev
  }

  function newImage() {
    autosave(function(ok) {
      if (!ok) { root.say("Autosave failed, kept this image"); return }
      root.resetDocument(Pixels.create(root.imgW, root.imgH))
      root.setPalette(root.themeColors())
      root.selectSlot(0)
      root.currentFile = ""
      root.fileName = ""
      root.writeState()
      root.say("New image")
    })
  }

  function openFiles() {
    pickingRef = false
    refreshFiles()
    dialog = "files"
  }

  // Restoring keeps the saved palette and fails silently.
  function loadFile(name, restoring) {
    closeDialog()
    autosave(function(saved) {
      if (!saved) root.say("Autosave failed, kept this image")
      else root.readFile(name, restoring)
    })
  }

  // name is relative to dir, or an absolute path from the browse dialog. Absolute
  // files are imported: the document is not tied to them, so saves go to dir.
  function readFile(name, restoring) {
    var external = name.charAt(0) === "/", base = name.split("/").pop()
    runJob(["base64", "-w0", external ? name : dir + "/" + name], "", function(ok, out) {
      if (!ok) { if (!restoring) root.say("Could not read " + base); return }
      var dec
      try { dec = Png.decode(Png.base64Decode(out), Pixels.MAX_SIDE) } catch (e) { root.say(e.message); return }
      root.resetDocument(dec)
      if (!restoring) root.setPalette(Pixels.mergePalette(Pixels.topColors(dec, Pixels.PALETTE_SIZE), root.themeColors(), Pixels.PALETTE_SIZE))
      root.selectSlot(Math.max(0, root.slot))
      root.currentFile = external ? "" : name
      root.fileName = base.replace(/\.png$/, "")
      root.writeState()
      root.say("Loaded " + base)
    })
  }

  // Out of process: QtQuick.Dialogs runs GTK in the shell and aborts it inside gvfs.
  Process {
    id: browser
    command: ["omarchy-file-select", "--title", "Load image", "--extensions", "png"]
    stdout: StdioCollector {
      onStreamFinished: { var path = text.trim(); if (path) root.loadFile(path, false) }
    }
    onExited: function(code) { if (code > 1) root.say("File chooser failed") }
  }

  function browseFiles() {
    closeDialog()
    browser.running = true
  }

  function exportImage(scale) {
    closeDialog()
    commitSelection()
    var base = Pixels.cleanName(fileName) || currentFile || Pixels.timestampName(new Date())
    var bg = exportBgs[exportBg].color
    var name = "Export/" + Pixels.exportName(base, scale), bytes = Png.encode(bg ? Pixels.flatten(img, Pixels.parseHex(bg)) : img, scale)
    var write = function() { root.writeBytes(name, bytes, function(ok) { if (ok) root.say("Exported " + name) }) }
    exists(name, function(yes) { if (yes) root.ask("Overwrite " + name + "?", write); else write() })
  }

  property int exportIndex: 1
  readonly property var exportScales: [4, 8, 16]
  property int exportBg: 0
  readonly property var exportBgs: [{ label: "Transparent", color: "" }, { label: "Grey", color: Pixels.GREY_BG },
                                    { label: "White", color: "#ffffff" }, { label: "Black", color: "#000000" },
                                    { label: "Current " + current, color: current }]

  function exportKey(event) {
    if (event.key === Qt.Key_Escape) closeDialog()
    else if (event.key === Qt.Key_Left || event.text === "h") exportIndex = Math.max(0, exportIndex - 1)
    else if (event.key === Qt.Key_Right || event.text === "l") exportIndex = Math.min(exportScales.length - 1, exportIndex + 1)
    else if (event.key === Qt.Key_Up || event.text === "k") exportBg = (exportBg + exportBgs.length - 1) % exportBgs.length
    else if (event.key === Qt.Key_Down || event.text === "j") exportBg = (exportBg + 1) % exportBgs.length
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) exportImage(exportScales[exportIndex])
    else if (event.text === "4") exportImage(4)
    else if (event.text === "8") exportImage(8)
    else if (event.text === "1") exportImage(16)
    else return false
    return true
  }

  function refreshFiles() {
    runJob(["sh", "-c", 'mkdir -p "$1" && cd "$1" && ls -t -- *.png 2>/dev/null', "sh", dir], "", function(ok, out) {
      root.files = out.split("\n").filter(function(n) { return n !== "" })
    })
  }

  // ------------------------------------------------------------ state file
  FileView {
    id: stateFile
    path: root.home + "/.local/state/omarchy/burningcat.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: themeFile
    path: Color.currentThemePath + "/colors.toml"
    blockLoading: true
    printErrors: false
  }

  function writeState() {
    stateFile.setText(JSON.stringify({ lastFile: currentFile, palette: colors.slice(0, Pixels.PALETTE_SIZE), extras: colors.slice(Pixels.PALETTE_SIZE), width: imgW, height: imgH, background: bg, keys: Pixels.overridesOf(keymap), referenceFile: refFile }, null, 2) + "\n")
  }

  function restoreState() {
    var s = {}
    try { s = JSON.parse(stateFile.text() || "{}") } catch (e) { s = {} }
    var w = Number(s.width), h = Number(s.height)
    if (w >= 1 && h >= 1 && w <= Pixels.MAX_SIDE && h <= Pixels.MAX_SIDE) resetDocument(Pixels.create(w, h))
    var valid = function(c) { return Pixels.parseHex(c) >= 0 ? String(c).toLowerCase() : "" }
    // Older state files hold 10 slots; pad them instead of dropping the user's palette.
    var palette = Array.isArray(s.palette) && s.palette.length >= 10
      ? s.palette.concat(new Array(Pixels.PALETTE_SIZE).fill("")).slice(0, Pixels.PALETTE_SIZE).map(valid)
      : themeColors()
    var extras = Array.isArray(s.extras) && s.extras.length === Pixels.EXTRA_COLORS.length ? s.extras.map(valid) : Pixels.EXTRA_COLORS
    colors = palette.concat(extras)
    bg = Pixels.BACKGROUNDS.indexOf(s.background) >= 0 ? s.background : s.greyBg === true ? Pixels.GREY_BG : ""  // greyBg: older state files
    keymap = Pixels.bindings(s.keys)
    selectSlot(0)
    if (typeof s.lastFile === "string" && Pixels.cleanName(s.lastFile) === s.lastFile) loadFile(s.lastFile, true)
    if (typeof s.referenceFile === "string" && s.referenceFile && Pixels.cleanName(s.referenceFile) === s.referenceFile) {
      refFile = s.referenceFile
      openReference(refFile, true)
    }
  }

  Component.onCompleted: {
    restoreState()
    refreshFiles()
  }

  onOpenedChanged: {
    if (opened) { refreshFiles(); return }
    drag = null
    if (dialog !== "") dialog = ""
    autosave()
    writeState()
  }

  // ------------------------------------------------------------ job runner
  // One external command at a time, in order, so a save is always on disk
  // before the listing or load that follows it.
  property var jobs: []

  function runJob(cmd, input, done) {
    jobs.push({ cmd: cmd, input: input || "", done: done })
    startNext()
  }

  function startNext() {
    if (runner.busy || !jobs.length) return
    var j = jobs[0]
    runner.busy = true
    runner.exitCode = -1
    runner.streamDone = false
    runner.exitDone = false
    runner.stdinEnabled = j.input !== ""
    runner.command = j.cmd
    runner.running = true
  }

  function finishJob() {
    if (!runner.streamDone || !runner.exitDone) return
    var j = jobs.shift()
    runner.busy = false
    try { j.done(runner.exitCode === 0, out.text || "") } catch (e) { console.warn("burningcat:", e) }
    Qt.callLater(startNext)
  }

  Process {
    id: runner
    property bool busy: false
    property int exitCode: -1
    property bool streamDone: false
    property bool exitDone: false
    stdout: StdioCollector {
      id: out
      onStreamFinished: { runner.streamDone = true; root.finishJob() }
    }
    onStarted: {
      var j = root.jobs[0]
      if (j && j.input !== "") { write(j.input); stdinEnabled = false }
    }
    onExited: function(code) {
      exitCode = code
      exitDone = true
      root.finishJob()
    }
  }

  // ------------------------------------------------------------ UI
  component IconButton: Button {
    property int glyph: 0
    iconText: glyph ? String.fromCodePoint(glyph) : ""
    horizontalPadding: Style.spacing.xs
    verticalPadding: Style.spacing.xs
    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight
  }

  component FocusFrame: Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.width: 2
    border.color: Color.accent
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  FloatingWindow {
    id: window
    title: "BurningCat"
    color: Color.background
    implicitWidth: 900
    implicitHeight: 760
    visible: false

    onVisibleChanged: if (!visible && !root.closingFromHost && root.opened) root.requestClose()

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.textEditing) return
        if (root.handleKey(event)) event.accepted = true
      }

      Column {
        id: layout
        anchors.fill: parent
        anchors.margins: Style.spacing.lg
        spacing: Style.spacing.lg

        Row {
          id: topRow
          spacing: Style.spacing.lg

          Column {
            id: sidebar
            spacing: Style.spacing.lg

            Grid {
              columns: 2
              spacing: Style.spacing.xs

              Repeater {
                model: Pixels.SIZES
                IconButton {
                  required property int modelData
                  text: String(modelData)
                  fontSize: Style.font.caption
                  selected: root.imgW === modelData && root.imgH === modelData
                  tooltipText: modelData + "x" + modelData
                  onClicked: root.resizeCanvas(modelData, modelData)
                }
              }
              IconButton {
                text: "…"
                selected: !(root.imgW === root.imgH && Pixels.SIZES.indexOf(root.imgW) >= 0)
                tooltipText: "Custom size (max " + Pixels.MAX_SIDE + "x" + Pixels.MAX_SIDE + ")"
                onClicked: { widthField.text = String(root.imgW); heightField.text = String(root.imgH); root.dialog = "size"; widthField.forceActiveFocus() }
              }
              IconButton {
                text: "⤢"
                tooltipText: "Upscale (" + root.keyOf("upscale") + ")"
                onClicked: root.dialog = "upscale"
              }
              IconButton { glyph: 0xf02c1; selected: root.grid; tooltipText: "Grid (" + root.keyOf("grid") + ")"; onClicked: root.grid = !root.grid }
              IconButton { glyph: 0xf0139; selected: root.bgMenu; tooltipText: "Background (" + root.keyOf("background") + ")"; onClicked: root.runAction("background") }
              IconButton { glyph: 0xf06ec; tooltipText: "Zoom out (" + root.keyOf("zoomOut") + ")"; onClicked: root.zoom(-1) }
              IconButton { glyph: 0xf06ed; tooltipText: "Zoom in (" + root.keyOf("zoomIn") + ")"; onClicked: root.zoom(1) }

              Repeater {
                model: root.tools
                IconButton {
                  required property var modelData
                  glyph: modelData.icon
                  selected: root.tool === modelData.id
                  tooltipText: modelData.label + " (" + root.keyOf(modelData.id) + ")"
                  onClicked: root.setTool(modelData.id)
                }
              }

              IconButton { glyph: 0xf054c; tooltipText: "Undo (ctrl+z)"; onClicked: root.undo() }
              IconButton { glyph: 0xf044e; tooltipText: "Redo (ctrl+y)"; onClicked: root.redo() }
              IconButton { glyph: 0xf030c; tooltipText: "Keybindings (" + root.keyOf("keys") + ")"; onClicked: root.dialog = "keys" }
            }

            // Options of the active tool.
            Grid {
              anchors.horizontalCenter: parent.horizontalCenter
              columns: 2
              spacing: Style.spacing.xs

              Repeater {
                model: root.tool === "pixel" && !root.bgMenu ? Pixels.PEN_SIZES : []
                IconButton {
                  required property int modelData
                  width: root.slotSize
                  height: width
                  text: String(modelData)
                  fontSize: Style.font.caption
                  selected: root.penSize === modelData
                  tooltipText: "Pen " + modelData + "x" + modelData + " (" + root.keyOf("pixel") + " cycles)"
                  onClicked: root.penSize = modelData
                }
              }
              Repeater {
                model: root.tool === "select" && !root.bgMenu ? [["flipH", "↔", "Flip horizontal"], ["flipV", "↕", "Flip vertical"],
                                                 ["rotateCcw", "⟲", "Rotate counter-clockwise"], ["rotateCw", "⟳", "Rotate clockwise"]] : []
                IconButton {
                  required property var modelData
                  width: root.slotSize
                  height: width
                  text: modelData[1]
                  fontSize: Style.font.caption
                  tooltipText: modelData[2] + " (" + root.keyOf(modelData[0]) + ")"
                  onClicked: root.runAction(modelData[0])
                }
              }
              Repeater {
                model: root.bgMenu ? Pixels.BACKGROUNDS : []
                Rectangle {
                  required property string modelData
                  width: root.slotSize
                  height: width
                  color: modelData || "transparent"
                  border.width: root.bg === modelData ? 2 : 1
                  border.color: root.bg === modelData ? Color.accent : Util.alpha(Color.popups.text, 0.3)

                  Grid {
                    anchors.fill: parent
                    anchors.margins: parent.border.width  // keep the selection border visible
                    visible: !parent.modelData
                    columns: 4
                    Repeater {
                      model: 16
                      Rectangle {
                        required property int index
                        width: parent.width / 4
                        height: width
                        color: Util.alpha(Color.foreground, (index + Math.floor(index / 4)) % 2 ? 0.06 : 0.16)
                      }
                    }
                  }
                  MouseArea { anchors.fill: parent; onClicked: root.setBg(parent.modelData) }
                }
              }
            }
          }

          PixelView {
            id: view
            width: root.paneW
            height: root.viewH
            img: root.img
            imgW: root.imgW
            imgH: root.imgH
            px: root.px
            grid: root.grid
            bg: root.bg
            cursorX: root.cursorX
            cursorY: root.cursorY
            cursorSize: root.tool === "pixel" ? root.penSize : 1
            sel: root.sel
            preview: root.preview
            previewColor: root.current
            onPointerPressed: function(x, y, b, m) { root.onPointerPressed(x, y, b, m) }
            onPointerMoved: function(x, y, m, p) { root.onPointerMoved(x, y, m, p) }
            onPointerReleased: function(x, y, m) { root.onPointerReleased(x, y, m) }
            onZoomRequested: function(d) { if (root.onRef) root.switchSide(); root.zoom(d) }

            FocusFrame { visible: !!root.refImg && !root.onRef }
          }

          PixelView {
            id: refView
            visible: !!root.refImg
            width: root.paneW
            height: root.viewH
            img: root.refImg
            imgW: root.refImg ? root.refImg.w : 1
            imgH: root.refImg ? root.refImg.h : 1
            px: root.refPx
            grid: root.grid
            bg: root.bg
            cursorX: root.refCursorX
            cursorY: root.refCursorY
            sel: root.refSel
            onPointerPressed: function(x, y, b, m) { root.onRefPressed(x, y, b, m) }
            onPointerMoved: function(x, y, m, p) { root.onRefMoved(x, y, m, p) }
            onPointerReleased: function(x, y, m) { root.refStartPt = null }
            onZoomRequested: function(d) { if (!root.onRef) root.switchSide(); root.zoom(d) }

            FocusFrame { visible: root.onRef }
          }
        }

        Row {
          id: bottomRow
          spacing: Style.spacing.lg

          Component {
            id: slotCell
            Rectangle {
              required property int modelData   // slot index
              readonly property string hex: root.colors[modelData] || ""
              width: root.slotSize
              height: width
              color: hex || "transparent"
              border.width: modelData === root.slot ? 2 : 1
              border.color: modelData === root.slot ? Color.accent : Util.alpha(Color.popups.text, hex ? 0.3 : 0.15)

              Label {
                anchors.centerIn: parent
                visible: !parent.hex
                text: parent.modelData < 20 ? String((parent.modelData + 1) % 10) : root.keyOf("slot" + (parent.modelData + 1))
                opacity: 0.4
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(m) {
                  root.selectSlot(parent.modelData)
                  if (m.button === Qt.RightButton) root.dialog = "slot"
                }
              }
            }
          }

          // The two extra slots (21, 22) sit in front of the number-key slots.
          Grid {
            columns: 1
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            Repeater { model: [20, 21]; delegate: slotCell }
          }

          Grid {
            columns: 10
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            Repeater { model: 20; delegate: slotCell }
          }

          IconButton { anchors.top: fileOps.top; glyph: 0xf0415; tooltipText: "Add color (" + root.keyOf("addColor") + ")"; onClicked: root.openPicker("add") }

          Grid {
            id: fileOps
            columns: 3
            spacing: Style.spacing.xs
            leftPadding: Style.spacing.xxl * 2  // sets file operations apart from the palette
            anchors.verticalCenter: parent.verticalCenter

            IconButton { glyph: 0xf0752; tooltipText: "New (" + root.keyOf("new") + ")"; onClicked: root.newImage() }
            IconButton { glyph: 0xf0193; tooltipText: "Save (" + root.keyOf("save") + ")"; onClicked: root.save() }
            IconButton { glyph: 0xf0cfb; tooltipText: "Save as (ctrl+s)"; onClicked: root.saveAs() }
            IconButton { glyph: 0xf0770; tooltipText: "Load (" + root.keyOf("load") + ")"; onClicked: root.openFiles() }
            IconButton { glyph: 0xf0207; tooltipText: "Export (" + root.keyOf("export") + ")"; onClicked: root.dialog = "export" }
          }
        }

        TextField {
          id: fileField
          width: topRow.width
          placeholderText: "Untitled (saved with a timestamp name)"
          text: root.fileName
          onTextEdited: root.fileName = text
          onAccepted: {
            var saving = root.savingAs
            keys.forceActiveFocus()  // clears savingAs
            if (saving) root.save()
          }
          onActiveFocusChanged: if (!activeFocus) root.savingAs = false
          Keys.onEscapePressed: keys.forceActiveFocus()
        }

        Item {
          id: statusRow
          width: topRow.width
          implicitHeight: statusText.implicitHeight

          Row {
            id: statusText
            spacing: Style.spacing.md

            Label { visible: !!root.refImg; text: root.onRef ? "Reference" : "Image"; color: Color.accent }
            Label { text: root.onRef ? root.refCursorX + "," + root.refCursorY : root.cursorX + "," + root.cursorY }
            Label { text: root.toolLabel(root.tool) + (root.tool === "pixel" ? " " + root.penSize + "x" + root.penSize : ""); opacity: 0.7 }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.font.bodySmall
              height: width
              color: root.current
              border.width: 1
              border.color: Util.alpha(Color.popups.text, 0.3)
            }
            Label { text: root.current }
            Label { text: root.imgW + "x" + root.imgH + "  " + root.px + "x"; opacity: 0.5 }
          }

          Label {
            anchors.right: parent.right
            anchors.left: statusText.right
            anchors.leftMargin: Style.spacing.md
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: root.note || (root.rev !== root.savedRev ? "●" : "")
            color: Color.accent
          }
        }
      }

      // ---------------------------------------------------------- dialogs
      ColorPicker {
        id: picker
        anchors.fill: parent
        opened: root.dialog === "picker"
        returnFocus: keys
        onAccepted: function(hex) { root.pickerAccepted(hex) }
        onCanceled: root.closeDialog()
        onPipetteRequested: root.startPipette("picker")
      }

      FileList {
        id: fileList
        anchors.fill: parent
        opened: root.dialog === "files"
        dir: root.dir
        files: root.files
        title: root.pickingRef ? "Open reference" : "Load"
        onChosen: function(name) { if (root.pickingRef) root.openReference(name, false); else root.loadFile(name, false) }
        onBrowse: if (root.pickingRef) root.say("A reference opens from " + root.dir); else root.browseFiles()
        onCanceled: root.closeDialog()
      }

      Dialog {
        anchors.fill: parent
        opened: root.dialog === "export"
        title: "Export"
        onCanceled: root.closeDialog()

        Row {
          spacing: Style.spacing.lg
          Repeater {
            model: root.exportScales
            Button {
              required property int index
              required property int modelData
              text: modelData + "x"
              bordered: true
              hasCursor: root.exportIndex === index
              onClicked: root.exportImage(modelData)
            }
          }
        }
        Row {
          spacing: Style.spacing.lg
          Repeater {
            model: root.exportBgs
            Button {
              required property int index
              required property var modelData
              text: modelData.label
              bordered: true
              selected: root.exportBg === index
              onClicked: root.exportBg = index
            }
          }
        }
        Label { text: (root.imgW * root.exportScales[root.exportIndex]) + "x" + (root.imgH * root.exportScales[root.exportIndex]) + " px · ←→ scale, ↑↓ background"; opacity: 0.6 }
      }

      Dialog {
        anchors.fill: parent
        opened: root.dialog === "upscale"
        title: "Upscale (each pixel becomes a block)"
        onCanceled: root.closeDialog()

        Row {
          spacing: Style.spacing.lg
          Repeater {
            model: root.upscaleFactors
            Button {
              required property int index
              required property int modelData
              text: modelData + "x"
              bordered: true
              hasCursor: root.upscaleIndex === index
              onClicked: root.upscale(modelData)
            }
          }
        }
        Label { text: (root.imgW * root.upscaleFactors[root.upscaleIndex]) + "x" + (root.imgH * root.upscaleFactors[root.upscaleIndex]) + " px (max " + Pixels.MAX_SIDE + ")"; opacity: 0.6 }
      }

      Dialog {
        id: sizeDialog
        anchors.fill: parent
        opened: root.dialog === "size"
        title: "Canvas size"
        returnFocus: keys
        onCanceled: root.closeDialog()

        function apply() {
          var w = parseInt(widthField.text, 10), h = parseInt(heightField.text, 10)
          if (!(w >= 1 && h >= 1 && w <= Pixels.MAX_SIDE && h <= Pixels.MAX_SIDE)) { root.say("Size must be 1 to " + Pixels.MAX_SIDE); return }
          root.closeDialog()
          root.resizeCanvas(w, h)
        }

        Row {
          spacing: Style.spacing.md
          TextField {
            id: widthField
            width: Style.space(60)
            validator: IntValidator { bottom: 1; top: Pixels.MAX_SIDE }
            onAccepted: heightField.forceActiveFocus()
            Keys.onEscapePressed: root.closeDialog()
          }
          Label { text: "x"; anchors.verticalCenter: parent.verticalCenter }
          TextField {
            id: heightField
            width: Style.space(60)
            validator: IntValidator { bottom: 1; top: Pixels.MAX_SIDE }
            onAccepted: sizeDialog.apply()
            Keys.onEscapePressed: root.closeDialog()
          }
        }
        Label { text: "Content is padded or cropped evenly"; opacity: 0.6 }
      }

      Dialog {
        anchors.fill: parent
        opened: root.dialog === "slot"
        title: "Color " + (root.slot + 1)
        onCanceled: root.closeDialog()

        Row {
          spacing: Style.spacing.lg
          Button { text: "Replace"; bordered: true; onClicked: root.openPicker("replace") }
          Button {
            text: "Delete"
            bordered: true
            onClicked: {
              var next = root.colors.slice()
              next[root.slot] = ""
              root.setColors(next)
              root.closeDialog()
            }
          }
        }
      }

      KeyMenu {
        id: keyMenu
        anchors.fill: parent
        opened: root.dialog === "keys"
        keymap: root.keymap
        onCanceled: root.closeDialog()
        onRebound: function(id, key) { root.rebindKey(id, key) }
        onReset: { root.keymap = Pixels.defaultBindings(); root.writeState(); root.say("Keybindings reset") }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        opened: root.dialog === "confirm"
        confirmText: "Overwrite"
        onCanceled: root.closeDialog()
        onConfirmed: {
          var action = root.pendingConfirm
          root.pendingConfirm = null
          root.closeDialog()
          if (action) action()
        }
      }
    }
  }
}
