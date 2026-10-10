# PNG encoding and decoding in JavaScript, not through Canvas

The spec planned to write PNGs with `Canvas.save()` and read them back via
`drawImage` + `getImageData`. The build-order prototype showed both fail for
pixel art: `Canvas.save()` returned false, and on a scale-2 output
`getImageData` returns device pixels, so a loaded image is not pixel-exact.

So `Png.js` encodes (8-bit RGBA, RLE deflate) and decodes (all color types and
bit depths, non-interlaced) PNGs in plain JS, and bytes cross into the shell as
base64 through `base64` / `wl-copy` / `wl-paste` processes. Display still uses
`Canvas` (one canvas pixel per image pixel, scaled without smoothing), which
is exact at any scale.

Consequences: exact pixels at any device-pixel ratio; the codec runs under
node tests; exports compress well (repeated rows and runs), photos poorly;
interlaced PNGs are refused.
