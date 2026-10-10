.pragma library

// Pixel model for the editor. Images are {w, h, data: Uint32Array} with
// pixels as 0xAARRGGBB, 0 = transparent. Everything here is free of QML
// types so it runs under plain node for the tests.

var MAX_SIDE = 512
var SIZES = [16, 32, 64, 128]
var HISTORY_LIMIT = 100
var PALETTE_SIZE = 20
// Extra slots 21/22 after the palette; new and loaded images leave them alone.
var EXTRA_COLORS = ["#000000", "#ffffff"]

function create(w, h) { return { w: w, h: h, data: new Uint32Array(w * h) } }

function clone(img) { return { w: img.w, h: img.h, data: img.data.slice() } }

function inside(img, x, y) { return x >= 0 && y >= 0 && x < img.w && y < img.h }

function get(img, x, y) { return inside(img, x, y) ? img.data[y * img.w + x] : 0 }

// Returns true when the pixel changed.
function set(img, x, y, c) {
  if (!inside(img, x, y)) return false
  var i = y * img.w + x
  if (img.data[i] === c) return false
  img.data[i] = c
  return true
}

function isEmpty(img) {
  for (var i = 0; i < img.data.length; i++) if (img.data[i] !== 0) return false
  return true
}

// ------------------------------------------------------------------ colors

function parseHex(hex) {
  var m = /^#?([0-9a-fA-F]{6})$/.exec(String(hex || "").trim())
  return m ? (0xff000000 | parseInt(m[1], 16)) >>> 0 : -1
}

function toHex(c) { return "#" + ("000000" + (c & 0xffffff).toString(16)).slice(-6) }

function toCss(c) {
  var a = c >>> 24
  return a === 255 ? toHex(c) : "rgba(" + ((c >>> 16) & 255) + "," + ((c >>> 8) & 255) + "," + (c & 255) + "," + (a / 255) + ")"
}

function hsvToHex(h, s, v) {
  var f = function(n) {
    var k = (n + h / 60) % 6
    return Math.round(255 * (v - v * s * Math.max(0, Math.min(k, 4 - k, 1))))
  }
  return toHex((f(5) << 16) | (f(3) << 8) | f(1))
}

// Returns {h: 0..360, s: 0..1, v: 0..1}.
function hexToHsv(hex) {
  var c = parseHex(hex)
  if (c < 0) return { h: 0, s: 0, v: 0 }
  var r = ((c >>> 16) & 255) / 255, g = ((c >>> 8) & 255) / 255, b = (c & 255) / 255
  var max = Math.max(r, g, b), d = max - Math.min(r, g, b), h = 0
  if (d > 0) {
    if (max === r) h = 60 * (((g - b) / d) % 6)
    else if (max === g) h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4)
  }
  return { h: (h + 360) % 360, s: max === 0 ? 0 : d / max, v: max }
}

// HSV <-> HSL keep the shared hue; s, v, l are 0..1. Returns {s, l} / {s, v}.
function hsvToHsl(s, v) {
  var l = v * (1 - s / 2), m = Math.min(l, 1 - l)
  return { s: m === 0 ? 0 : (v - l) / m, l: l }
}

function hslToHsv(s, l) {
  var v = l + s * Math.min(l, 1 - l)
  return { s: v === 0 ? 0 : 2 * (1 - l / v), v: v }
}

// ------------------------------------------------------------------ tools

// 4-connected flood fill. Returns the number of changed pixels.
function fill(img, x, y, c) {
  if (!inside(img, x, y)) return 0
  var target = get(img, x, y)
  if (target === c) return 0
  var stack = [y * img.w + x], n = 0
  while (stack.length) {
    var i = stack.pop()
    if (img.data[i] !== target) continue
    img.data[i] = c
    n++
    var px = i % img.w
    if (px > 0) stack.push(i - 1)
    if (px < img.w - 1) stack.push(i + 1)
    if (i >= img.w) stack.push(i - img.w)
    if (i < img.data.length - img.w) stack.push(i + img.w)
  }
  return n
}

// Bresenham line, both endpoints included.
function line(x0, y0, x1, y1) {
  var pts = [], dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0)
  var sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy
  for (;;) {
    pts.push({ x: x0, y: y0 })
    if (x0 === x1 && y0 === y1) return pts
    var e2 = 2 * err
    if (e2 >= dy) { err += dy; x0 += sx }
    if (e2 <= dx) { err += dx; y0 += sy }
  }
}

// Ellipse inscribed in the box (x0,y0)-(x1,y1), any width/height parity.
// Zingl 2012, "A Rasterizing Algorithm for Drawing Curves", plotEllipseRect.
function ellipse(x0, y0, x1, y1) {
  var pts = []
  var a = Math.abs(x1 - x0), b = Math.abs(y1 - y0), b1 = b & 1
  var dx = 4 * (1 - a) * b * b, dy = 4 * (b1 + 1) * a * a
  var err = dx + dy + b1 * a * a, e2
  if (x0 > x1) { x0 = x1; x1 += a }
  if (y0 > y1) y0 = y1
  y0 += (b + 1) >> 1
  y1 = y0 - b1
  a *= 8 * a
  b1 = 8 * b * b
  do {
    pts.push({ x: x1, y: y0 }, { x: x0, y: y0 }, { x: x0, y: y1 }, { x: x1, y: y1 })
    e2 = 2 * err
    if (e2 <= dy) { y0++; y1--; err += dy += a }
    if (e2 >= dx || 2 * err > dy) { x0++; x1--; err += dx += b1 }
  } while (x0 <= x1)
  while (y0 - y1 <= b) {  // flat ellipses (a = 1) stop early; finish the tips
    pts.push({ x: x0 - 1, y: y0 }, { x: x1 + 1, y: y0++ }, { x: x0 - 1, y: y1 }, { x: x1 + 1, y: y1-- })
  }
  return pts
}

function polygon(verts) {
  var pts = []
  for (var i = 0; i < verts.length; i++) {
    var a = verts[i], b = verts[(i + 1) % verts.length]
    pts = pts.concat(line(a.x, a.y, b.x, b.y))
  }
  return pts
}

// Regular-ish n-gon inscribed in the box, vertex positions rounded to pixels.
function ngon(n, rot, l, t, r, b) {
  var cx = (l + r) / 2, cy = (t + b) / 2, rx = (r - l) / 2, ry = (b - t) / 2, v = []
  for (var i = 0; i < n; i++) {
    var ang = rot + i * 2 * Math.PI / n
    v.push({ x: Math.round(cx + rx * Math.cos(ang)), y: Math.round(cy + ry * Math.sin(ang)) })
  }
  return v
}

// With keepRatio the box becomes square (lines snap to 0/45/90 degrees).
function constrain(kind, x0, y0, x1, y1, keepRatio) {
  if (!keepRatio) return { x: x1, y: y1 }
  var dx = x1 - x0, dy = y1 - y0
  if (kind === "line") {
    var adx = Math.abs(dx), ady = Math.abs(dy)
    if (adx > 2 * ady) return { x: x1, y: y0 }
    if (ady > 2 * adx) return { x: x0, y: y1 }
  }
  var m = Math.max(Math.abs(dx), Math.abs(dy))
  return { x: x0 + (dx < 0 ? -m : m), y: y0 + (dy < 0 ? -m : m) }
}

// Outline pixels for a shape dragged from (x0,y0) to (x1,y1), deduplicated.
function shape(kind, x0, y0, x1, y1, keepRatio) {
  var e = constrain(kind, x0, y0, x1, y1, keepRatio)
  x1 = e.x; y1 = e.y
  var l = Math.min(x0, x1), r = Math.max(x0, x1), t = Math.min(y0, y1), b = Math.max(y0, y1)
  var pts
  if (kind === "line") pts = line(x0, y0, x1, y1)
  else if (kind === "rectangle") pts = polygon([{ x: l, y: t }, { x: r, y: t }, { x: r, y: b }, { x: l, y: b }])
  else if (kind === "circle") pts = ellipse(l, t, r, b)
  else if (kind === "triangle") pts = polygon([{ x: Math.round((l + r) / 2), y: t }, { x: r, y: b }, { x: l, y: b }])
  else if (kind === "hexagon") pts = polygon(ngon(6, 0, l, t, r, b))
  else if (kind === "octagon") pts = polygon(ngon(8, Math.PI / 8, l, t, r, b))
  else return []
  var seen = {}, out = []
  for (var i = 0; i < pts.length; i++) {
    var k = pts[i].x + "," + pts[i].y
    if (!seen[k]) { seen[k] = true; out.push(pts[i]) }
  }
  return out
}

// ------------------------------------------------------------------ regions

function normRect(x0, y0, x1, y1) {
  return { x: Math.min(x0, x1), y: Math.min(y0, y1), w: Math.abs(x1 - x0) + 1, h: Math.abs(y1 - y0) + 1 }
}

// Clip a rect to the image; null when nothing is left.
function clipRect(img, r) {
  var x = Math.max(0, r.x), y = Math.max(0, r.y)
  var w = Math.min(img.w, r.x + r.w) - x, h = Math.min(img.h, r.y + r.h) - y
  return w > 0 && h > 0 ? { x: x, y: y, w: w, h: h } : null
}

function extract(img, r) {
  var out = create(r.w, r.h)
  for (var y = 0; y < r.h; y++)
    for (var x = 0; x < r.w; x++) out.data[y * r.w + x] = get(img, r.x + x, r.y + y)
  return out
}

function clear(img, r) {
  for (var y = r.y; y < r.y + r.h; y++)
    for (var x = r.x; x < r.x + r.w; x++) set(img, x, y, 0)
}

// Draw buf onto img at (ox, oy); transparent buf pixels leave img untouched.
function blit(img, buf, ox, oy) {
  for (var y = 0; y < buf.h; y++)
    for (var x = 0; x < buf.w; x++) {
      var c = buf.data[y * buf.w + x]
      if (c !== 0) set(img, ox + x, oy + y, c)
    }
}

function flipH(buf) {
  var out = create(buf.w, buf.h)
  for (var y = 0; y < buf.h; y++)
    for (var x = 0; x < buf.w; x++) out.data[y * buf.w + x] = buf.data[y * buf.w + buf.w - 1 - x]
  return out
}

function flipV(buf) {
  var out = create(buf.w, buf.h)
  for (var y = 0; y < buf.h; y++)
    for (var x = 0; x < buf.w; x++) out.data[y * buf.w + x] = buf.data[(buf.h - 1 - y) * buf.w + x]
  return out
}

function rotate(buf, clockwise) {
  var out = create(buf.h, buf.w)
  for (var y = 0; y < buf.h; y++)
    for (var x = 0; x < buf.w; x++) {
      var nx = clockwise ? buf.h - 1 - y : y, ny = clockwise ? x : buf.w - 1 - x
      out.data[ny * out.w + nx] = buf.data[y * buf.w + x]
    }
  return out
}

// Pad or crop evenly on all sides; an odd difference puts the extra pixel
// on the right and top.
function resize(img, nw, nh) {
  var dx = nw - img.w, dy = nh - img.h
  var ox = (dx < 0 ? -1 : 1) * Math.floor(Math.abs(dx) / 2)
  var oy = (dy < 0 ? -1 : 1) * Math.ceil(Math.abs(dy) / 2)
  var out = create(nw, nh)
  blit(out, img, ox, oy)
  return out
}

// Nearest-neighbour upscale: every pixel becomes a k x k block.
function scale(img, k) {
  var out = create(img.w * k, img.h * k)
  for (var y = 0; y < out.h; y++)
    for (var x = 0; x < out.w; x++) out.data[y * out.w + x] = img.data[Math.floor(y / k) * img.w + Math.floor(x / k)]
  return out
}

// ------------------------------------------------------------------ palette

// The n most used visible colors as "#rrggbb", most used first, ties by first
// appearance.
function topColors(img, n) {
  var counts = {}, first = {}, order = []
  for (var i = 0; i < img.data.length; i++) {
    var c = img.data[i]
    if ((c >>> 24) === 0) continue
    var k = toHex(c)
    if (counts[k] === undefined) { counts[k] = 0; first[k] = order.length; order.push(k) }
    counts[k]++
  }
  order.sort(function(a, b) { return counts[b] - counts[a] || first[a] - first[b] })
  return order.slice(0, n)
}

// Fill up to `size` slots with `first`, then `fallback` colors not yet used.
function mergePalette(first, fallback, size) {
  var out = []
  var add = function(c) {
    var h = String(c || "").toLowerCase()
    if (parseHex(h) >= 0 && out.indexOf(h) < 0 && out.length < size) out.push(h)
  }
  first.forEach(add)
  fallback.forEach(add)
  while (out.length < size) out.push("")
  return out
}

var THEME_KEYS = [
  ["foreground", "color7"], ["background", "color0"], ["red", "color1"], ["green", "color2"],
  ["yellow", "color3"], ["blue", "color4"], ["magenta", "color5"], ["cyan", "color6"],
  ["accent"], ["muted", "color8"], ["bright_red", "color9"], ["bright_green", "color10"],
  ["bright_yellow", "color11"], ["bright_blue", "color12"], ["bright_magenta", "color13"], ["bright_cyan", "color14"],
]

// PALETTE_SIZE distinct colors from an Omarchy colors.toml, topped up from fallback.
function themePalette(toml, fallback) {
  var vals = {}
  String(toml || "").split("\n").forEach(function(line) {
    var m = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) vals[m[1]] = m[2]
  })
  var picked = THEME_KEYS.map(function(keys) {
    for (var i = 0; i < keys.length; i++) if (vals[keys[i]]) return vals[keys[i]]
    return ""
  })
  return mergePalette(picked, fallback || [], PALETTE_SIZE)
}

// ------------------------------------------------------------------ files

function pad2(n) { return (n < 10 ? "0" : "") + n }

function timestampName(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    + "_" + pad2(d.getHours()) + "-" + pad2(d.getMinutes()) + "-" + pad2(d.getSeconds()) + ".png"
}

// User-typed filename to a bare "<name>.png", or "" when unusable.
function cleanName(name) {
  var n = String(name || "").trim().replace(/\.png$/i, "")
  if (!n || /[\/\\\0]/.test(n) || n.charAt(0) === ".") return ""
  return n + ".png"
}

function exportName(name, scale) { return String(name).replace(/\.png$/i, "") + "_" + scale + "x.png" }

// ------------------------------------------------------------------ keybindings

// Rebindable single-key actions as [id, label, default key]. A key is the
// typed character (event.text), so an uppercase letter means shift+letter.
var ACTIONS = [
  ["pixel", "Pixel", "p"], ["eyedropper", "Eyedropper", "i"], ["select", "Select", "v"], ["fill", "Color pot", "b"],
  ["line", "Line", "l"], ["rectangle", "Rectangle", "r"], ["circle", "Circle", "C"], ["triangle", "Triangle", "t"],
  ["hexagon", "Hexagon", "h"], ["octagon", "Octagon", "O"],
  ["erase", "Remove pixel / selection", "c"],
  ["flipH", "Flip horizontal", "f"], ["flipV", "Flip vertical", "F"],
  ["rotateCw", "Rotate clockwise", "]"], ["rotateCcw", "Rotate counter-clockwise", "["],
  ["slot21", "Color slot 21", "z"], ["slot22", "Color slot 22", "x"],
  ["addColor", "Add color", "a"], ["pipette", "Screen pipette", "I"],
  ["grid", "Grid", "g"], ["background", "Grey background", "k"], ["zoomIn", "Zoom in", "+"], ["zoomOut", "Zoom out", "-"],
  ["new", "New", "n"], ["save", "Save", "s"], ["load", "Load", "o"], ["export", "Export", "e"], ["upscale", "Upscale", "u"],
  ["keys", "Keybindings", "K"], ["quit", "Quit", "q"],
]

// Digits pick colors and space draws, so neither can be bound.
function bindable(key) { return typeof key === "string" && key.length === 1 && !/[0-9\s]/.test(key) }

function defaultBindings() {
  var map = {}
  ACTIONS.forEach(function(a) { map[a[0]] = a[2] })
  return map
}

// Bind id to key. The action that held key takes id's old key, so every
// action keeps exactly one key. Returns the swapped action id or "".
function rebind(map, id, key) {
  if (map[id] === undefined || !bindable(key) || map[id] === key) return ""
  var other = actionFor(map, key)
  if (other) map[other] = map[id]
  map[id] = key
  return other
}

// Defaults with the user's {id: key} overrides applied; bad entries are skipped.
function bindings(overrides) {
  var map = defaultBindings()
  for (var id in (overrides || {})) rebind(map, id, overrides[id])
  return map
}

// The entries that differ from the defaults, for the state file.
function overridesOf(map) {
  var def = defaultBindings(), out = {}
  for (var id in map) if (map[id] !== def[id]) out[id] = map[id]
  return out
}

function actionFor(map, key) {
  for (var id in map) if (map[id] === key) return id
  return ""
}

function keyLabel(key) { return key && key !== key.toLowerCase() ? "shift+" + key.toLowerCase() : key }

// ------------------------------------------------------------------ history

// Undo/redo of whole-image snapshots (size included, so resizes undo too).
function History() { this.undo = []; this.redo = [] }

History.prototype.push = function(img) {
  this.undo.push(clone(img))
  if (this.undo.length > HISTORY_LIMIT) this.undo.shift()
  this.redo = []
}

// Returns the image to show, or null when there is nothing to undo.
History.prototype.back = function(current) {
  if (!this.undo.length) return null
  this.redo.push(clone(current))
  return this.undo.pop()
}

History.prototype.forward = function(current) {
  if (!this.redo.length) return null
  this.undo.push(clone(current))
  return this.redo.pop()
}
