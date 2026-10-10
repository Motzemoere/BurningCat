// Logic tests for Pixels.js and Png.js.
//
//   node tests/logic.test.mjs

import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { deflateSync, inflateSync } from "node:zlib"

const here = dirname(fileURLToPath(import.meta.url))
const load = (file, names) => {
  const src = readFileSync(join(here, "..", file), "utf8").replace(".pragma library", "")
  const G = {}
  new Function("exports", `${src}\nfor (const k of ${JSON.stringify(names)}) exports[k] = eval(k)`)(G)
  return G
}
const P = load("Pixels.js", ["create", "get", "set", "isEmpty", "parseHex", "toHex", "toCss", "hsvToHex", "hexToHsv", "hsvToHsl", "hslToHsv", "PALETTE_SIZE",
  "fill", "line", "ellipse", "shape", "normRect", "clipRect", "extract", "clear", "blit", "flipH", "flipV", "rotate",
  "resize", "topColors", "mergePalette", "themePalette", "timestampName", "cleanName", "exportName", "History"])
const Z = load("Png.js", ["base64Encode", "base64Decode", "crc32", "inflate", "Deflater", "encode", "decode"])

let pass = 0, fail = 0
const t = (name, cond) => {
  if (cond) { pass++; console.log("  ok   " + name) }
  else { fail++; console.log("  FAIL " + name) }
}
const group = (name) => console.log("\n" + name)
const RED = 0xffff0000, BLUE = 0xff0000ff, HALF = 0x800000ff
const img = (w, h, rows) => { const i = P.create(w, h); rows && rows.forEach((v, k) => i.data[k] = v); return i }
const eq = (a, b) => a.w === b.w && a.h === b.h && a.data.every((v, i) => v === b.data[i])
const has = (pts, x, y) => pts.some(p => p.x === x && p.y === y)

group("colors")
t("parseHex opaque", P.parseHex("#ff0000") === RED)
t("parseHex rejects junk", P.parseHex("red") === -1 && P.parseHex("#fff") === -1)
t("toHex", P.toHex(BLUE) === "#0000ff")
t("toCss keeps alpha", P.toCss(HALF).startsWith("rgba(0,0,255,0.50"))
t("hsv round trip", P.hsvToHex(P.hexToHsv("#3a7bd5").h, P.hexToHsv("#3a7bd5").s, P.hexToHsv("#3a7bd5").v) === "#3a7bd5")
t("hsv red", P.hsvToHex(0, 1, 1) === "#ff0000")
{
  const near = (a, b) => Math.abs(a - b) < 1e-9
  const l = P.hsvToHsl(1, 1)
  t("hsl of pure red", near(l.s, 1) && near(l.l, 0.5))
  t("hsl of white/black", near(P.hsvToHsl(0, 1).l, 1) && P.hsvToHsl(0, 0).s === 0)
  const v = P.hslToHsv(0.4, 0.3), back = P.hsvToHsl(v.s, v.v)
  t("hsl round trip", near(back.s, 0.4) && near(back.l, 0.3))
  t("hsl black", P.hslToHsv(0.5, 0).v === 0 && P.hslToHsv(0.5, 0).s === 0)
}

group("fill")
{
  const i = img(3, 3, [0, RED, 0, RED, 0, RED, 0, RED, 0])
  t("4-connected: centre alone", P.fill(i, 1, 1, BLUE) === 1 && P.get(i, 0, 0) === 0)
  t("same colour is a no-op", P.fill(i, 1, 1, BLUE) === 0)
  const j = P.create(16, 16)
  t("fills whole empty canvas", P.fill(j, 5, 5, RED) === 256)
}

group("shapes")
{
  const l = P.line(0, 0, 5, 2)
  t("line endpoints", has(l, 0, 0) && has(l, 5, 2) && l.length === 6)
  const c = P.shape("circle", 0, 0, 7, 7, false)
  t("circle within box", c.every(p => p.x >= 0 && p.x <= 7 && p.y >= 0 && p.y <= 7))
  t("circle touches all four sides", [0, 7].every(v => c.some(p => p.x === v)) && [0, 7].every(v => c.some(p => p.y === v)))
  t("circle symmetric", c.every(p => has(c, 7 - p.x, p.y) && has(c, p.x, 7 - p.y)))
  const flat = P.shape("circle", 0, 0, 1, 6, false)
  t("thin ellipse is closed at the tips", has(flat, 0, 0) || has(flat, 1, 0))
  const r = P.shape("rectangle", 2, 2, 5, 4, false)
  t("rectangle outline count", r.length === 2 * 4 + 2 * 1)
  t("ctrl squares a rectangle", P.shape("rectangle", 0, 0, 5, 2, true).some(p => p.y === 5))
  t("ctrl snaps line horizontal", P.shape("line", 0, 0, 9, 1, true).every(p => p.y === 0))
  for (const k of ["triangle", "hexagon", "octagon"]) {
    const s = P.shape(k, 0, 0, 10, 10, false)
    t(k + " inside box and non-empty", s.length > 8 && s.every(p => p.x >= 0 && p.x <= 10 && p.y >= 0 && p.y <= 10))
  }
  t("single point shapes", P.shape("circle", 3, 3, 3, 3, false).length === 1 && P.shape("rectangle", 3, 3, 3, 3).length === 1)
}

group("regions")
{
  const i = img(3, 2, [1, 2, 3, 4, 5, 6])
  t("flipH", P.flipH(i).data.join() === "3,2,1,6,5,4")
  t("flipV", P.flipV(i).data.join() === "4,5,6,1,2,3")
  const cw = P.rotate(i, true)
  t("rotate cw", cw.w === 2 && cw.h === 3 && cw.data.join() === "4,1,5,2,6,3")
  t("rotate ccw undoes cw", eq(P.rotate(cw, false), i))
  t("extract/clear/blit", (() => {
    const j = img(3, 2, [1, 2, 3, 4, 5, 6]), r = P.normRect(2, 1, 1, 0)
    const b = P.extract(j, r); P.clear(j, r); P.blit(j, b, 0, 0)
    return j.data.join() === "2,3,0,5,6,0"
  })())
  t("blit skips transparent", (() => { const j = img(2, 1, [RED, RED]); P.blit(j, img(2, 1, [0, BLUE]), 0, 0); return j.data.join() === [RED, BLUE].join() })())
  t("clipRect", JSON.stringify(P.clipRect(i, { x: -1, y: 1, w: 3, h: 5 })) === '{"x":0,"y":1,"w":2,"h":1}')
}

group("resize")
{
  const i = img(2, 2, [1, 2, 3, 4])
  const g = P.resize(i, 5, 5)
  t("grow odd: extra column right, extra row top", P.get(g, 1, 2) === 1 && P.get(g, 2, 3) === 4)
  const s = P.resize(P.resize(i, 5, 5), 2, 2)
  t("crop back restores", eq(s, i))
  const c = P.resize(img(5, 5, [...Array(25).keys()]), 2, 2)
  t("crop odd: extra removed right and top", c.data.join() === "11,12,16,17")
}

group("palette")
{
  const i = img(4, 1, [BLUE, RED, RED, 0])
  t("topColors by count", P.topColors(i, 10).join() === "#ff0000,#0000ff")
  const p = P.mergePalette(["#ff0000"], ["#FF0000", "#00ff00"], 4)
  t("merge dedupes and pads", p.join() === "#ff0000,#00ff00,,")
  const theme = 'accent = "#b59790"\nforeground = "#FAFCFB"\nbackground = "#0c0b0c"\nred = "#c38b7b"\n'
    + 'green = "#87a9b0"\nyellow = "#6B5E73"\nblue = "#b59790"\nmagenta = "#c4d8e2"\ncyan = "#a5a0b6"\nmuted = "#584e51"\n'
  const tp = P.themePalette(theme, ["#111111", "#222222"])
  t("theme palette fills PALETTE_SIZE distinct", tp.length === P.PALETTE_SIZE && new Set(tp.filter(Boolean)).size === 11 && tp[0] === "#fafcfb")
  t("theme palette fallback when empty", P.themePalette("", ["#111111"])[0] === "#111111")
}

group("files")
t("timestamp", P.timestampName(new Date(2026, 9, 10, 14, 30, 5)) === "2026-10-10_14-30-05.png")
t("cleanName adds .png", P.cleanName(" cat ") === "cat.png" && P.cleanName("cat.PNG") === "cat.png")
t("cleanName refuses paths", P.cleanName("../x") === "" && P.cleanName("a/b") === "" && P.cleanName(".hidden") === "" && P.cleanName("") === "")
t("exportName", P.exportName("cat.png", 8) === "cat_8x.png")

group("history")
{
  const h = new P.History(), a = img(1, 1, [1])
  h.push(a)
  const b = img(2, 1, [2, 2])
  const back = h.back(b)
  t("undo returns previous incl. size", back.w === 1 && back.data[0] === 1)
  t("redo returns next", h.forward(back).w === 2)
  t("nothing to redo after push", (h.push(a), h.forward(a) === null))
}

group("png")
{
  const bytes = Uint8Array.from({ length: 1000 }, (_, i) => (i * 7919) & 255)
  t("base64 round trip", Z.base64Decode(Z.base64Encode(bytes)).every((v, i) => v === bytes[i]))
  t("base64 matches node", Z.base64Encode(bytes) === Buffer.from(bytes).toString("base64"))
  const d = new Z.Deflater(); d.write(new Uint8Array(5000)); d.write(bytes)
  const zd = d.finish()
  const back = inflateSync(zd)
  t("our deflate inflates with zlib", back.length === 6000 && back.subarray(5000).every((v, i) => v === bytes[i]))
  t("zero run compresses", zd.length < 1200)
  for (const level of [0, 1, 9]) {
    const src = Buffer.concat([Buffer.from(bytes), Buffer.alloc(3000, 7), Buffer.from("hello hello hello hello")])
    const ours = Z.inflate(deflateSync(src, { level }))
    t("inflate zlib level " + level, Buffer.from(ours).equals(src))
  }
  const art = img(3, 2, [RED, 0, HALF, BLUE, 0xff123456, 0])
  t("encode/decode round trip", eq(Z.decode(Z.encode(art)), art))
  const big = Z.decode(Z.encode(art, 4))
  t("4x export nearest-neighbour", big.w === 12 && big.h === 8 && P.get(big, 3, 3) === RED && P.get(big, 4, 0) === 0 && P.get(big, 11, 7) === 0 && P.get(big, 4, 4) === 0xff123456)
  t("decode refuses too large", (() => { try { Z.decode(Z.encode(P.create(300, 2)), 256); return false } catch (e) { return /300x2/.test(e.message) } })())
  t("decode refuses non-png", (() => { try { Z.decode(new Uint8Array(20)); return false } catch (e) { return /Not a PNG/.test(e.message) } })())
}

group("png from other encoders")
{
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length)
    const td = Buffer.concat([Buffer.from(type), data])
    const crc = Buffer.alloc(4); crc.writeUInt32BE(Z.crc32(td, 0, td.length))
    return Buffer.concat([len, td, crc])
  }
  const png = (w, h, depth, ctype, rows, extra = []) => {
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = depth; ihdr[9] = ctype
    return new Uint8Array(Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), ...extra,
      chunk("IDAT", deflateSync(Buffer.from(rows), { level: 9 })), chunk("IEND", Buffer.alloc(0))]))
  }
  // 2-bit palette, 3x1, index 1 transparent via tRNS
  const pal = png(3, 1, 2, 3, [0, 0b00011000], [chunk("PLTE", Buffer.from([255, 0, 0, 0, 255, 0, 0, 0, 255])), chunk("tRNS", Buffer.from([255, 0]))])
  t("2-bit palette + tRNS", Z.decode(pal).data.join() === [RED, 0, BLUE].join())
  // 8-bit RGB with Paeth and Average filters
  const rgb = png(2, 3, 8, 2, [0, 255, 0, 0, 0, 0, 255, 4, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])
  const r = Z.decode(rgb)
  t("RGB Paeth/Average filters", r.data[0] === RED && r.data[1] === BLUE && r.data[2] === RED && r.data[3] === BLUE && r.data[4] === 0xff7f0000 && r.data[5] === 0xff3f007f)
  // 16-bit gray+alpha
  const ga = png(1, 1, 16, 4, [0, 0x80, 0x00, 0xff, 0xff])
  t("16-bit gray alpha", Z.decode(ga).data[0] === 0xff808080)
  // 1-bit gray
  const g1 = png(9, 1, 1, 0, [0, 0b10000000, 0b10000000])
  const g = Z.decode(g1).data
  t("1-bit gray", g[0] === 0xffffffff && g[1] === 0xff000000 && g[8] === 0xffffffff)
}

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail ? 1 : 0)
