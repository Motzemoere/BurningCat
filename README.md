# PixelArt

A small pixel art editor as an Omarchy shell plugin: a bar widget that opens
an editor panel, styled live by the current Omarchy theme. The feature spec,
including the full keybinding list, is [features.md](features.md).

## Install

```bash
omarchy plugin add https://github.com/Motzemoere/PixelArt.git --enable
```

Requires Omarchy 4, `wl-clipboard` (copy/paste) and `hyprpicker` (screen
pipette). Add the toggle keybind to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "PixelArt", "omarchy-shell shell toggle motzemoere.pixelart")
```

## Files

- Images: `~/Pictures/PixelArt/*.png`
- Editor state (last file, palette, size): `~/.local/state/omarchy/pixelart.json`

## Beyond the spec's keybindings

- `shift+arrows` move the selection
- right click with the color pot fills with transparency
- `ctrl+wheel` zooms, `wheel` / `shift+wheel` scroll
- color picker: arrows change saturation/value, `shift+arrows` hue, `tab` the
  hex field, `p` or `shift+i` the screen pipette
- export dialog: `4`, `8`, `1` (16x) or arrows + `return`

## Development

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/motzemoere.pixelart
omarchy plugin enable motzemoere.pixelart
node tests/logic.test.mjs
```

The shell caches compiled QML, so run `omarchy-restart-shell` to load edits.
