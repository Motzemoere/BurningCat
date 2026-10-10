.pragma library

// PNG codec on plain byte arrays. Images are {w, h, data: Uint32Array} with
// pixels as 0xAARRGGBB, 0 = transparent. Bytes move in and out of QML as
// base64 because QML file APIs only speak text.

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function base64Encode(bytes) {
  var out = []
  for (var i = 0; i < bytes.length; i += 3) {
    var n = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0)
    out.push(B64[n >> 18 & 63], B64[n >> 12 & 63],
             i + 1 < bytes.length ? B64[n >> 6 & 63] : "=",
             i + 2 < bytes.length ? B64[n & 63] : "=")
  }
  return out.join("")
}

function base64Decode(str) {
  var s = String(str).replace(/[^A-Za-z0-9+/]/g, "")
  var out = new Uint8Array(Math.floor(s.length * 3 / 4))
  var o = 0, acc = 0, bits = 0
  for (var i = 0; i < s.length; i++) {
    acc = (acc << 6) | B64.indexOf(s[i])
    bits += 6
    if (bits >= 8) { bits -= 8; out[o++] = (acc >> bits) & 255 }
  }
  return out.subarray(0, o)
}

var CRC_TABLE = (function() {
  var t = new Uint32Array(256)
  for (var n = 0; n < 256; n++) {
    var c = n
    for (var k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c >>> 0
  }
  return t
})()

function crc32(bytes, start, end) {
  var c = 0xffffffff
  for (var i = start; i < end; i++) c = CRC_TABLE[(c ^ bytes[i]) & 255] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

// ------------------------------------------------------------------ inflate
// RFC 1950/1951 decoder: stored, fixed and dynamic Huffman blocks.

var LEN_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
var LEN_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
var DIST_BASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
var DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
var CL_ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

// Canonical Huffman table: counts per length and symbols sorted by code.
function huffman(lengths) {
  var counts = new Uint16Array(16), offs = new Uint16Array(16)
  for (var i = 0; i < lengths.length; i++) counts[lengths[i]]++
  counts[0] = 0
  for (i = 1; i < 16; i++) offs[i] = offs[i - 1] + counts[i - 1]
  var symbols = new Uint16Array(lengths.length)
  for (i = 0; i < lengths.length; i++) if (lengths[i]) symbols[offs[lengths[i]]++] = i
  return { counts: counts, symbols: symbols }
}

function inflate(src) {
  if (src.length < 2 || (src[0] & 15) !== 8 || ((src[0] << 8) | src[1]) % 31 !== 0)
    throw new Error("Not a zlib stream")
  var pos = 2, bitBuf = 0, bitCnt = 0
  var out = new Uint8Array(Math.max(1024, src.length * 4)), o = 0

  function ensure(n) {
    if (o + n <= out.length) return
    var bigger = new Uint8Array(Math.max(out.length * 2, o + n))
    bigger.set(out.subarray(0, o))
    out = bigger
  }
  function bits(n) {
    while (bitCnt < n) {
      if (pos >= src.length) throw new Error("Truncated image data")
      bitBuf |= src[pos++] << bitCnt
      bitCnt += 8
    }
    var v = bitBuf & ((1 << n) - 1)
    bitBuf >>>= n
    bitCnt -= n
    return v
  }
  function decodeSym(h) {
    var code = 0, first = 0, index = 0
    for (var len = 1; len < 16; len++) {
      code |= bits(1)
      var count = h.counts[len]
      if (code - first < count) return h.symbols[index + code - first]
      index += count
      first = (first + count) << 1
      code <<= 1
    }
    throw new Error("Bad Huffman code")
  }

  var fixedLit = null, fixedDist = null
  var last = 0
  while (!last) {
    last = bits(1)
    var type = bits(2)
    if (type === 0) {
      bitBuf = 0; bitCnt = 0
      if (pos + 4 > src.length) throw new Error("Truncated image data")
      var len = src[pos] | (src[pos + 1] << 8)
      pos += 4
      if (pos + len > src.length) throw new Error("Truncated image data")
      ensure(len)
      out.set(src.subarray(pos, pos + len), o)
      o += len; pos += len
      continue
    }
    var lit, dist
    if (type === 1) {
      if (!fixedLit) {
        var l = new Uint8Array(288)
        for (var i = 0; i < 288; i++) l[i] = i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8
        fixedLit = huffman(l)
        var d = new Uint8Array(30)
        for (i = 0; i < 30; i++) d[i] = 5
        fixedDist = huffman(d)
      }
      lit = fixedLit; dist = fixedDist
    } else if (type === 2) {
      var hlit = bits(5) + 257, hdist = bits(5) + 1, hclen = bits(4) + 4
      var clLens = new Uint8Array(19)
      for (i = 0; i < hclen; i++) clLens[CL_ORDER[i]] = bits(3)
      var cl = huffman(clLens)
      var lens = new Uint8Array(hlit + hdist)
      for (i = 0; i < hlit + hdist;) {
        var sym = decodeSym(cl)
        if (sym < 16) { lens[i++] = sym; continue }
        var prev = 0, rep
        if (sym === 16) {
          if (i === 0) throw new Error("Bad code lengths")
          prev = lens[i - 1]; rep = 3 + bits(2)
        } else if (sym === 17) rep = 3 + bits(3)
        else rep = 11 + bits(7)
        if (i + rep > hlit + hdist) throw new Error("Bad code lengths")
        while (rep--) lens[i++] = prev
      }
      lit = huffman(lens.subarray(0, hlit))
      dist = huffman(lens.subarray(hlit))
    } else {
      throw new Error("Bad deflate block")
    }
    for (;;) {
      sym = decodeSym(lit)
      if (sym < 256) { ensure(1); out[o++] = sym; continue }
      if (sym === 256) break
      sym -= 257
      if (sym >= 29) throw new Error("Bad length code")
      var length = LEN_BASE[sym] + bits(LEN_EXTRA[sym])
      var ds = decodeSym(dist)
      if (ds >= 30) throw new Error("Bad distance code")
      var back = DIST_BASE[ds] + bits(DIST_EXTRA[ds])
      if (back > o) throw new Error("Bad distance")
      ensure(length)
      for (var k = 0; k < length; k++, o++) out[o] = out[o - back]
    }
  }
  return out.subarray(0, o)
}

// ------------------------------------------------------------------ deflate
// Fixed-Huffman encoder whose only matches are distance-1 runs (like zlib's
// Z_RLE). Paired with Sub/Up row filters that is what pixel art needs: flat
// areas and nearest-neighbour upscaling turn into long zero runs.
// shortcut: no general LZ77, so photos compress poorly; add it if photos matter.

function Deflater() {
  this.out = []
  this.acc = 0
  this.cnt = 0
  this.prev = -1
  this.run = 0
  this.adlerA = 1
  this.adlerB = 0
  this.out.push(0x78, 0x01)
  this.put(1, 1)      // BFINAL
  this.put(1, 2)      // BTYPE fixed
}

Deflater.prototype.put = function(value, n) {
  this.acc |= value << this.cnt
  this.cnt += n
  while (this.cnt >= 8) {
    this.out.push(this.acc & 255)
    this.acc >>>= 8
    this.cnt -= 8
  }
}

// Huffman codes go MSB first into the LSB-first bit stream.
Deflater.prototype.putCode = function(code, n) {
  var rev = 0
  for (var i = 0; i < n; i++) { rev = (rev << 1) | (code & 1); code >>= 1 }
  this.put(rev, n)
}

Deflater.prototype.literal = function(v) {
  if (v < 144) this.putCode(0x30 + v, 8)
  else if (v < 256) this.putCode(0x190 + v - 144, 9)
  else if (v < 280) this.putCode(v - 256, 7)
  else this.putCode(0xc0 + v - 280, 8)
}

Deflater.prototype.match = function(len) {
  var i = 28
  while (LEN_BASE[i] > len) i--
  this.literal(257 + i)
  if (LEN_EXTRA[i]) this.put(len - LEN_BASE[i], LEN_EXTRA[i])
  this.putCode(0, 5)  // distance code 0 = 1 back
}

Deflater.prototype.flushRun = function() {
  var n = this.run
  while (n >= 3) {
    var m = Math.min(258, n)
    if (n - m > 0 && n - m < 3) m = n - 3
    this.match(m)
    n -= m
  }
  while (n-- > 0) this.literal(this.prev)
  this.run = 0
}

Deflater.prototype.write = function(bytes) {
  var a = this.adlerA, b = this.adlerB
  for (var i = 0; i < bytes.length; i++) {
    var v = bytes[i]
    a += v; b += a
    if ((i & 4095) === 4095) { a %= 65521; b %= 65521 }
    if (v === this.prev) { this.run++; continue }
    this.flushRun()
    this.literal(v)
    this.prev = v
  }
  this.adlerA = a % 65521
  this.adlerB = b % 65521
}

Deflater.prototype.finish = function() {
  this.flushRun()
  this.literal(256)
  if (this.cnt > 0) this.put(0, 8 - this.cnt)
  var adler = ((this.adlerB << 16) | this.adlerA) >>> 0
  this.out.push(adler >>> 24, (adler >>> 16) & 255, (adler >>> 8) & 255, adler & 255)
  return new Uint8Array(this.out)
}

// ------------------------------------------------------------------ PNG

var SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10]

function u32(b, p) { return ((b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]) >>> 0 }

function pushU32(arr, v) { arr.push(v >>> 24, (v >>> 16) & 255, (v >>> 8) & 255, v & 255) }

function pushChunk(arr, type, data) {
  pushU32(arr, data.length)
  var start = arr.length
  for (var i = 0; i < 4; i++) arr.push(type.charCodeAt(i))
  for (i = 0; i < data.length; i++) arr.push(data[i])
  pushU32(arr, crc32(arr, start, arr.length))
}

// Encode as 8-bit RGBA, upscaled `scale`x with nearest-neighbour. Returns
// a Uint8Array of PNG bytes.
function encode(img, scale) {
  var k = Math.max(1, Math.floor(scale || 1))
  var W = img.w * k, H = img.h * k, stride = W * 4
  var arr = SIGNATURE.slice()
  pushChunk(arr, "IHDR", [W >>> 24, (W >>> 16) & 255, (W >>> 8) & 255, W & 255,
                          H >>> 24, (H >>> 16) & 255, (H >>> 8) & 255, H & 255, 8, 6, 0, 0, 0])
  var z = new Deflater()
  var row = new Uint8Array(stride), filtered = new Uint8Array(stride + 1)
  var upRow = new Uint8Array(stride + 1)
  upRow[0] = 2  // repeated rows: Up filter, all zeros
  for (var y = 0; y < img.h; y++) {
    for (var x = 0; x < img.w; x++) {
      var c = img.data[y * img.w + x]
      for (var r = 0; r < k; r++) {
        var p = (x * k + r) * 4
        row[p] = (c >>> 16) & 255; row[p + 1] = (c >>> 8) & 255; row[p + 2] = c & 255; row[p + 3] = c >>> 24
      }
    }
    filtered[0] = 1  // Sub
    for (var i = 0; i < stride; i++) filtered[i + 1] = (row[i] - (i >= 4 ? row[i - 4] : 0)) & 255
    z.write(filtered)
    for (r = 1; r < k; r++) z.write(upRow)
  }
  pushChunk(arr, "IDAT", z.finish())
  pushChunk(arr, "IEND", [])
  return new Uint8Array(arr)
}

function paeth(a, b, c) {
  var p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c)
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c
}

// Decode any non-interlaced PNG. Throws Error with a user-facing message.
// Images larger than maxSide on either axis are refused before inflating.
function decode(bytes, maxSide) {
  for (var i = 0; i < 8; i++) if (bytes[i] !== SIGNATURE[i]) throw new Error("Not a PNG file")
  var pos = 8, w = 0, h = 0, depth = 0, ctype = 0, interlace = 0
  var palette = null, trns = null, idat = [], idatLen = 0
  while (pos + 8 <= bytes.length) {
    var len = u32(bytes, pos)
    var type = String.fromCharCode(bytes[pos + 4], bytes[pos + 5], bytes[pos + 6], bytes[pos + 7])
    var start = pos + 8
    if (start + len > bytes.length) throw new Error("Truncated PNG")
    var data = bytes.subarray(start, start + len)
    if (type === "IHDR") {
      w = u32(data, 0); h = u32(data, 4); depth = data[8]; ctype = data[9]; interlace = data[12]
      if (maxSide && (w > maxSide || h > maxSide))
        throw new Error("Image is " + w + "x" + h + ", the maximum is " + maxSide + "x" + maxSide)
    } else if (type === "PLTE") palette = data
    else if (type === "tRNS") trns = data
    else if (type === "IDAT") { idat.push(data); idatLen += len }
    else if (type === "IEND") break
    pos = start + len + 4
  }
  if (!w || !h) throw new Error("PNG has no image header")
  // shortcut: Adam7 interlacing is refused; pixel-art PNGs are almost never interlaced.
  if (interlace) throw new Error("Interlaced PNGs are not supported")
  var channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ctype]
  if (!channels) throw new Error("Unsupported PNG color type " + ctype)
  if (ctype === 3 && !palette) throw new Error("PNG palette missing")

  var z = new Uint8Array(idatLen), zo = 0
  for (i = 0; i < idat.length; i++) { z.set(idat[i], zo); zo += idat[i].length }
  var raw = inflate(z)

  var bpp = Math.max(1, (channels * depth) >> 3)
  var stride = (w * channels * depth + 7) >> 3
  if (raw.length < h * (stride + 1)) throw new Error("Truncated image data")
  var cur = new Uint8Array(stride), prev = new Uint8Array(stride)
  var out = new Uint32Array(w * h)
  var maxv = (1 << depth) - 1
  for (var y = 0; y < h; y++) {
    var f = raw[y * (stride + 1)], base = y * (stride + 1) + 1
    for (i = 0; i < stride; i++) {
      var a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0
      var v = raw[base + i]
      if (f === 1) v += a
      else if (f === 2) v += b
      else if (f === 3) v += (a + b) >> 1
      else if (f === 4) v += paeth(a, b, c)
      else if (f !== 0) throw new Error("Bad PNG filter")
      cur[i] = v & 255
    }
    for (var x = 0; x < w; x++) {
      var s = function(ch) {  // sample ch of pixel x, scaled to 0..255
        if (depth === 8) return cur[x * channels + ch]
        if (depth === 16) return cur[(x * channels + ch) * 2]
        var bit = (x * channels + ch) * depth
        var raw8 = (cur[bit >> 3] >> (8 - depth - (bit & 7))) & maxv
        return ctype === 3 ? raw8 : Math.round(raw8 * 255 / maxv)
      }
      var R, G, B, A = 255
      if (ctype === 3) {
        var idx = s(0)
        R = palette[idx * 3]; G = palette[idx * 3 + 1]; B = palette[idx * 3 + 2]
        if (trns && idx < trns.length) A = trns[idx]
      } else if (ctype === 0 || ctype === 4) {
        R = G = B = s(0)
        if (ctype === 4) A = s(1)
        else if (trns && rawSample(cur, x, 0, channels, depth) === ((trns[0] << 8) | trns[1])) A = 0
      } else {
        R = s(0); G = s(1); B = s(2)
        if (ctype === 6) A = s(3)
        else if (trns && rawSample(cur, x, 0, channels, depth) === ((trns[0] << 8) | trns[1])
                 && rawSample(cur, x, 1, channels, depth) === ((trns[2] << 8) | trns[3])
                 && rawSample(cur, x, 2, channels, depth) === ((trns[4] << 8) | trns[5])) A = 0
      }
      out[y * w + x] = A === 0 ? 0 : (((A << 24) | (R << 16) | (G << 8) | B) >>> 0)
    }
    var t = prev; prev = cur; cur = t
  }
  return { w: w, h: h, data: out }
}

// Unscaled sample value, for comparing against tRNS keys.
function rawSample(row, x, ch, channels, depth) {
  if (depth === 16) { var p = (x * channels + ch) * 2; return (row[p] << 8) | row[p + 1] }
  if (depth === 8) return row[x * channels + ch]
  var bit = (x * channels + ch) * depth
  return (row[bit >> 3] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1)
}
