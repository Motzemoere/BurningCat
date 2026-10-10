import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Pixels.js" as Pixels
import "Png.js" as Png

// Bar widget whose panel is the pixel editor. Drawing logic lives in
// Pixels.js / Png.js; this file holds editor state, input and file I/O.
Panel {
  id: root
  moduleName: "motzemoere.pixelart"
  ipcTarget: "motzemoere.pixelart"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string home: Quickshell.env("HOME")
  readonly property string dir: home + "/Pictures/PixelArt"

  // ------------------------------------------------------------ editor state
  property var img: Pixels.create(32, 32)
  property int imgW: 32
  property int imgH: 32
  property var history: new Pixels.History()
  property var colors: Pixels.mergePalette([], [], 10)
  property int slot: 0
  property string current: "#ffffff"
  property string tool: "pixel"
  property bool grid: false
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
  property bool picking: false
  property string pipetteTarget: ""
  property string pickerMode: ""

  readonly property bool textEditing: fileField.activeFocus || picker.editing || widthField.activeFocus || heightField.activeFocus

  readonly property var tools: [
    { id: "pixel", icon: 0xf03eb, key: "p", label: "Pixel" },
    { id: "eyedropper", icon: 0xf020a, key: "i", label: "Eyedropper" },
    { id: "select", icon: 0xf0489, key: "v", label: "Select" },
    { id: "fill", icon: 0xf0266, key: "b", label: "Color pot" },
    { id: "line", icon: 0xf055e, key: "l", label: "Line" },
    { id: "rectangle", icon: 0xf0763, key: "r", label: "Rectangle" },
    { id: "circle", icon: 0xf0766, key: "c", label: "Circle" },
    { id: "triangle", icon: 0xf0537, key: "t", label: "Triangle" },
    { id: "hexagon", icon: 0xf02d9, key: "h", label: "Hexagon" },
    { id: "octagon", icon: 0xf03c4, key: "O", label: "Octagon" },
  ]
  readonly property var shapeTools: ["line", "rectangle", "circle", "triangle", "hexagon", "octagon"]
  readonly property var zoomSteps: [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]

  function toolLabel(id) {
    for (var i = 0; i < tools.length; i++) if (tools[i].id === id) return tools[i].label
    return id
  }

  // ------------------------------------------------------------ view sizing
  // The panel grows with the image size, never with zoom.
  function viewSide(n) { return Math.round(Math.min(720, 200 + n * 4)) }
  readonly property int chromeH: bottomRow.implicitHeight + fileField.implicitHeight + statusRow.implicitHeight + layout.spacing * 3
  readonly property int maxViewW: panel.availableCardWidth > 0 ? panel.availableCardWidth - panel.verticalContentInset - sidebar.implicitWidth - topRow.spacing : 720
  readonly property int maxViewH: panel.availableCardHeight > 0 ? panel.availableCardHeight - panel.verticalContentInset - chromeH : 720
  readonly property int viewW: Math.max(64, Math.min(viewSide(imgW), maxViewW))
  readonly property int viewH: Math.max(64, Math.min(viewSide(imgH), maxViewH))
  readonly property int fitPx: Math.max(1, Math.floor(Math.min(viewW / imgW, viewH / imgH)))

  function zoom(direction) {
    var steps = zoomSteps.concat([fitPx]).sort(function(a, b) { return a - b })
    var next = px
    if (direction > 0) { for (var i = 0; i < steps.length; i++) if (steps[i] > px) { next = steps[i]; break } }
    else { for (var j = steps.length - 1; j >= 0; j--) if (steps[j] < px) { next = steps[j]; break } }
    px = next
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
    var changed = []
    for (var i = 0; i < points.length; i++)
      if (Pixels.set(img, points[i].x, points[i].y, c)) changed.push(points[i])
    if (changed.length) { view.paintPixels(changed); rev++ }
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

  function pick(x, y) {
    var c = Pixels.get(img, x, y)
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
    tool = id
  }

  function isShape(t) { return shapeTools.indexOf(t) >= 0 }

  function updatePreview(a, b, keepRatio) {
    if (tool === "select") { sel = rectSel(a, b); return }
    preview = Pixels.shape(tool, a.x, a.y, b.x, b.y, keepRatio)
  }

  function commitShape(a, b, keepRatio) {
    pushHistory()
    drawPoints(Pixels.shape(tool, a.x, a.y, b.x, b.y, keepRatio), currentInt())
    cancelShape()
  }

  function cancelShape() {
    startPt = null
    preview = []
  }

  function fillAt(x, y, c) {
    commitSelection()
    pushHistory()
    if (Pixels.fill(img, x, y, c)) view.repaintAll()
  }

  // ------------------------------------------------------------ selection
  function rectSel(a, b) {
    var r = Pixels.clipRect(img, Pixels.normRect(a.x, a.y, b.x, b.y))
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
    if (!sel) { say("Nothing selected"); return false }
    var b = sel.buf || Pixels.extract(img, sel)
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

  // ------------------------------------------------------------ input
  function activate(keepRatio) {
    var p = { x: cursorX, y: cursorY }
    if (tool === "pixel") { commitSelection(); pushHistory(); drawPoints([p], currentInt()) }
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
    else root.close()
  }

  function onPointerPressed(x, y, button, mods) {
    keys.forceActiveFocus()
    setCursor(x, y)
    var erase = button === Qt.RightButton
    if (mods & Qt.AltModifier) { pick(x, y); return }
    drag = { last: { x: x, y: y }, move: false }
    if (tool === "pixel") { commitSelection(); pushHistory(); drawPoints([{ x: x, y: y }], erase ? 0 : currentInt()); drag.erase = erase }
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
    if (tool === "pixel") drawPoints(Pixels.line(drag.last.x, drag.last.y, x, y), drag.erase ? 0 : currentInt())
    else if (drag.move) moveSel(x - drag.last.x, y - drag.last.y)
    else if (startPt) updatePreview(startPt, { x: Math.max(0, Math.min(imgW - 1, x)), y: Math.max(0, Math.min(imgH - 1, y)) }, mods & Qt.ControlModifier)
    drag.last = p
    setCursor(x, y)
  }

  function onPointerReleased(x, y, mods) {
    if (drag && startPt && isShape(tool)) commitShape(startPt, { x: x, y: y }, mods & Qt.ControlModifier)
    else if (drag && startPt) startPt = null
    drag = null
  }

  function handleKey(event) {
    if (dialog === "picker") return picker.handleKey(event)
    if (dialog === "files") return fileList.handleKey(event)
    if (dialog === "confirm") return confirm.handleKey(event)
    if (dialog === "export") return exportKey(event)
    if (dialog !== "") {
      if (event.key === Qt.Key_Escape) { closeDialog(); return true }
      return false
    }

    var ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
    var k = event.key
    if (ctrl) {
      if (k === Qt.Key_Z) { shift ? redo() : undo(); return true }
      if (k === Qt.Key_Y) { redo(); return true }
      if (k === Qt.Key_C) { copySel(); return true }
      if (k === Qt.Key_X) { cutSel(); return true }
      if (k === Qt.Key_V) { paste(); return true }
    }

    var dx = k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : 0
    var dy = k === Qt.Key_Up ? -1 : k === Qt.Key_Down ? 1 : 0
    if (dx || dy) {
      if (shift && sel) moveSel(dx, dy)
      else moveCursor(dx, dy)
      return true
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { activate(ctrl); return true }
    if (k === Qt.Key_Delete || k === Qt.Key_Backspace) {
      if (sel) deleteSel()
      else { commitSelection(); pushHistory(); drawPoints([{ x: cursorX, y: cursorY }], 0) }
      return true
    }
    if (k === Qt.Key_Escape) { cancel(); return true }
    if (ctrl) return false

    var t = event.text
    for (var i = 0; i < tools.length; i++) if (tools[i].key === t) { setTool(tools[i].id); return true }
    if (t >= "0" && t <= "9" && t.length === 1) { selectSlot((Number(t) + 9) % 10); return true }
    switch (t) {
      case "n": newImage(); return true
      case "s": save(); return true
      case "o": openFiles(); return true
      case "e": dialog = "export"; return true
      case "q": root.close(); return true
      case "g": grid = !grid; return true
      case "+": case "=": zoom(1); return true
      case "-": zoom(-1); return true
      case "f": transformSel(Pixels.flipH); return true
      case "F": transformSel(Pixels.flipV); return true
      case "]": transformSel(function(b) { return Pixels.rotate(b, true) }); return true
      case "[": transformSel(function(b) { return Pixels.rotate(b, false) }); return true
      case "a": openPicker("add"); return true
      case "I": startPipette("add"); return true
    }
    return false
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
                    mode === "replace" ? "Replace color " + ((slot + 1) % 10) : "New color")
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

  // The panel hides while hyprpicker owns the screen, then comes back.
  function startPipette(target) {
    pipetteTarget = target
    picking = true
    root.close()
    pipetteDelay.restart()
  }

  Timer {
    id: pipetteDelay
    interval: 250
    onTriggered: pipette.running = true
  }

  Process {
    id: pipette
    command: ["sh", "-c", "hyprpicker -f hex -l -q 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        var m = /#[0-9a-f]{6}/.exec(text)
        root.picking = false
        root.open()
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
  function writeImage(name, bytes, r, quiet) {
    var doc = docId
    writeBytes(name, bytes, function(ok) {
      if (!ok) return
      if (!quiet) root.say("Saved " + name)
      if (doc !== root.docId) return
      root.currentFile = name
      root.fileName = name.replace(/\.png$/, "")
      root.savedRev = r
      root.writeState()
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

  // Never asks: a typed name that belongs to another file falls back to
  // this image's own file or a fresh timestamp name.
  function autosave() {
    commitSelection()
    if (rev === savedRev || Pixels.isEmpty(img)) return
    var bytes = Png.encode(img), r = rev
    var typed = Pixels.cleanName(fileName)
    var fallback = currentFile || Pixels.timestampName(new Date())
    if (!typed || typed === currentFile) { writeImage(currentFile || typed || fallback, bytes, r, true); return }
    exists(typed, function(yes) { root.writeImage(yes ? fallback : typed, bytes, r, true) })
  }

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
    autosave()
    resetDocument(Pixels.create(imgW, imgH))
    setColors(themeColors())
    selectSlot(0)
    currentFile = ""
    fileName = ""
    writeState()
    say("New image")
  }

  function openFiles() {
    refreshFiles()
    dialog = "files"
  }

  // Restoring keeps the saved palette and fails silently.
  function loadFile(name, restoring) {
    closeDialog()
    autosave()
    runJob(["base64", "-w0", dir + "/" + name], "", function(ok, out) {
      if (!ok) { if (!restoring) root.say("Could not read " + name); return }
      var dec
      try { dec = Png.decode(Png.base64Decode(out), Pixels.MAX_SIDE) } catch (e) { root.say(e.message); return }
      root.resetDocument(dec)
      if (!restoring) root.setColors(Pixels.mergePalette(Pixels.topColors(dec, 10), root.themeColors(), 10))
      root.selectSlot(Math.max(0, root.slot))
      root.currentFile = name
      root.fileName = name.replace(/\.png$/, "")
      root.writeState()
      root.say("Loaded " + name)
    })
  }

  function exportImage(scale) {
    closeDialog()
    commitSelection()
    var base = Pixels.cleanName(fileName) || currentFile || Pixels.timestampName(new Date())
    var name = Pixels.exportName(base, scale), bytes = Png.encode(img, scale)
    var write = function() { root.writeBytes(name, bytes, function(ok) { if (ok) root.say("Exported " + name) }) }
    exists(name, function(yes) { if (yes) root.ask("Overwrite " + name + "?", write); else write() })
  }

  property int exportIndex: 1
  readonly property var exportScales: [4, 8, 16]

  function exportKey(event) {
    if (event.key === Qt.Key_Escape) closeDialog()
    else if (event.key === Qt.Key_Left || event.text === "h") exportIndex = Math.max(0, exportIndex - 1)
    else if (event.key === Qt.Key_Right || event.text === "l") exportIndex = Math.min(2, exportIndex + 1)
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
    path: root.home + "/.local/state/omarchy/pixelart.json"
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
    stateFile.setText(JSON.stringify({ lastFile: currentFile, palette: colors, width: imgW, height: imgH }, null, 2) + "\n")
  }

  function restoreState() {
    var s = {}
    try { s = JSON.parse(stateFile.text() || "{}") } catch (e) { s = {} }
    var w = Number(s.width), h = Number(s.height)
    if (w >= 1 && h >= 1 && w <= Pixels.MAX_SIDE && h <= Pixels.MAX_SIDE) resetDocument(Pixels.create(w, h))
    colors = Array.isArray(s.palette) && s.palette.length === 10
      ? s.palette.map(function(c) { return Pixels.parseHex(c) >= 0 ? String(c).toLowerCase() : "" })
      : themeColors()
    selectSlot(0)
    if (typeof s.lastFile === "string" && Pixels.cleanName(s.lastFile) === s.lastFile) loadFile(s.lastFile, true)
  }

  Component.onCompleted: {
    restoreState()
    refreshFiles()
  }

  onOpenedChanged: {
    if (opened) { refreshFiles(); return }
    if (picking) return
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
    try { j.done(runner.exitCode === 0, out.text || "") } catch (e) { console.warn("pixelart:", e) }
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

  component Label: Text {
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xf03d8)
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(layout.implicitWidth + panel.verticalContentInset)
    contentHeight: panel.fittedContentHeight(layout.implicitHeight)

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
        spacing: Style.spacing.lg

        Row {
          id: topRow
          spacing: Style.spacing.lg

          Grid {
            id: sidebar
            columns: 2
            spacing: Style.spacing.xs

            Repeater {
              model: [16, 32, 64, 128]
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
              selected: !(root.imgW === root.imgH && [16, 32, 64, 128].indexOf(root.imgW) >= 0)
              tooltipText: "Custom size (max 256x256)"
              onClicked: { widthField.text = String(root.imgW); heightField.text = String(root.imgH); root.dialog = "size"; widthField.forceActiveFocus() }
            }
            IconButton { glyph: 0xf02c1; selected: root.grid; tooltipText: "Grid (g)"; onClicked: root.grid = !root.grid }
            IconButton { glyph: 0xf06ec; tooltipText: "Zoom out (-)"; onClicked: root.zoom(-1) }
            IconButton { glyph: 0xf06ed; tooltipText: "Zoom in (+)"; onClicked: root.zoom(1) }

            Repeater {
              model: root.tools
              IconButton {
                required property var modelData
                glyph: modelData.icon
                selected: root.tool === modelData.id
                tooltipText: modelData.label + " (" + (modelData.key === "O" ? "shift+o" : modelData.key) + ")"
                onClicked: root.setTool(modelData.id)
              }
            }

            IconButton { glyph: 0xf054c; tooltipText: "Undo (ctrl+z)"; onClicked: root.undo() }
            IconButton { glyph: 0xf044e; tooltipText: "Redo (ctrl+y)"; onClicked: root.redo() }
          }

          PixelView {
            id: view
            width: root.viewW
            height: root.viewH
            img: root.img
            imgW: root.imgW
            imgH: root.imgH
            px: root.px
            grid: root.grid
            cursorX: root.cursorX
            cursorY: root.cursorY
            sel: root.sel
            preview: root.preview
            previewColor: root.current
            onPointerPressed: function(x, y, b, m) { root.onPointerPressed(x, y, b, m) }
            onPointerMoved: function(x, y, m, p) { root.onPointerMoved(x, y, m, p) }
            onPointerReleased: function(x, y, m) { root.onPointerReleased(x, y, m) }
            onZoomRequested: function(d) { root.zoom(d) }
          }
        }

        Row {
          id: bottomRow
          spacing: Style.spacing.lg

          Grid {
            columns: 5
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: 10
              Rectangle {
                required property int index
                readonly property string hex: root.colors[index] || ""
                width: Style.space(22)
                height: width
                color: hex || "transparent"
                border.width: index === root.slot ? 2 : 1
                border.color: index === root.slot ? Color.accent : Util.alpha(Color.popups.text, hex ? 0.3 : 0.15)

                Label {
                  anchors.centerIn: parent
                  visible: !parent.hex
                  text: String((parent.index + 1) % 10)
                  opacity: 0.4
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(m) {
                    root.selectSlot(parent.index)
                    if (m.button === Qt.RightButton) root.dialog = "slot"
                  }
                }
              }
            }
          }

          Grid {
            columns: 3
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter

            IconButton { glyph: 0xf0415; tooltipText: "Add color (a)"; onClicked: root.openPicker("add") }
            IconButton { glyph: 0xf0752; tooltipText: "New (n)"; onClicked: root.newImage() }
            IconButton { glyph: 0xf0193; tooltipText: "Save (s)"; onClicked: root.save() }
            IconButton { glyph: 0xf0770; tooltipText: "Load (o)"; onClicked: root.openFiles() }
            IconButton { glyph: 0xf0207; tooltipText: "Export (e)"; onClicked: root.dialog = "export" }
          }
        }

        TextField {
          id: fileField
          width: topRow.width
          placeholderText: "Untitled (saved with a timestamp name)"
          text: root.fileName
          onTextEdited: root.fileName = text
          onAccepted: keys.forceActiveFocus()
          Keys.onEscapePressed: keys.forceActiveFocus()
        }

        Item {
          id: statusRow
          width: topRow.width
          implicitHeight: statusText.implicitHeight

          Row {
            id: statusText
            spacing: Style.spacing.md

            Label { text: root.cursorX + "," + root.cursorY }
            Label { text: root.toolLabel(root.tool); opacity: 0.7 }
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
        onChosen: function(name) { root.loadFile(name, false) }
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
        Label { text: (root.imgW * root.exportScales[root.exportIndex]) + "x" + (root.imgH * root.exportScales[root.exportIndex]) + " px"; opacity: 0.6 }
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
          if (!(w >= 1 && h >= 1 && w <= Pixels.MAX_SIDE && h <= Pixels.MAX_SIDE)) { root.say("Size must be 1 to 256"); return }
          root.closeDialog()
          root.resizeCanvas(w, h)
        }

        Row {
          spacing: Style.spacing.md
          TextField {
            id: widthField
            width: Style.space(60)
            validator: IntValidator { bottom: 1; top: 256 }
            onAccepted: heightField.forceActiveFocus()
            Keys.onEscapePressed: root.closeDialog()
          }
          Label { text: "x"; anchors.verticalCenter: parent.verticalCenter }
          TextField {
            id: heightField
            width: Style.space(60)
            validator: IntValidator { bottom: 1; top: 256 }
            onAccepted: sizeDialog.apply()
            Keys.onEscapePressed: root.closeDialog()
          }
        }
        Label { text: "Content is padded or cropped evenly"; opacity: 0.6 }
      }

      Dialog {
        anchors.fill: parent
        opened: root.dialog === "slot"
        title: "Color " + ((root.slot + 1) % 10)
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
