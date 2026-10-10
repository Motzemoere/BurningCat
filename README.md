# PixelArt

A small pixel art editor as an Omarchy shell plugin: a keybind opens it as a
normal tiled Hyprland window, styled live by the current Omarchy theme. The feature spec,
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
- Editor state (last file, palette, size, custom keybindings): `~/.local/state/omarchy/pixelart.json`

## Beyond the spec's keybindings

- `shift+arrows` move the selection
- right click with the color pot fills with transparency
- `k` toggles a light grey background instead of the checkerboard
- `ctrl+wheel` zooms, `wheel` / `shift+wheel` scroll
- color picker: `m` cycles HSV / RGB / HSL. HSV: arrows change saturation/value,
  `shift+arrows` hue. RGB / HSL: up/down pick a channel, left/right change it
  (`shift` for steps of 10). `tab` the hex field, `p` or `shift+i` the screen pipette
- export dialog: `4`, `8`, `1` (16x) or arrows + `return`
- upscale dialog: `2`, `3`, `4` or arrows + `return`

## Development

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/motzemoere.pixelart
omarchy plugin enable motzemoere.pixelart
node tests/logic.test.mjs
```

The shell caches compiled QML, so run `omarchy-restart-shell` to load edits.
