# PixelArt

Plugin to make pixel art similar to paint but with only selected features focused on pixel art. Follows the Omarchy color themes

## Platform
- Omarchy 4 shell plugin (`manifest.json`, installed with `omarchy plugin add`)
- Bar widget in the Omarchy top bar, clicking it opens the editor panel
- Plugin id: `motzemoere.pixelart`
- Keybind `SUPER + ALT + P` toggles the panel: `omarchy-shell shell toggle motzemoere.pixelart`
- The panel must receive keyboard input (required for keyboard driven operations)
- Tech stack: QML + JavaScript inside `omarchy-shell` (Quickshell), like omarchy-snake; no external dependencies besides `wl-clipboard` and `hyprpicker`
- Theme colors from the shell's `qs.Commons` singletons
- Canvas: pixel data as a JS array, drawn via QML `Canvas` (`putImageData`), PNG written with `Canvas.save()`
- Load/save dialog: own file list of `~/Pictures/PixelArt` (the shell has no file dialog; built-in `image-picker` plugin as model)
- Color picker: own QML hue/saturation picker
- State (last edited file, palette) in `~/.local/state/omarchy/pixelart.json`
- Empty canvas is not autosaved
- Drawing logic (pixels, fill, shapes, undo, resize, palette extraction) in plain JS files with `node` tests; QML only renders and handles input

## Build order
1. Prototype (throwaway): panel opens via bar widget and keybind, receives keyboard input, `Canvas.save()` writes a PNG, PNG loads back into pixel data. If keyboard input fails in a panel, switch to an overlay before continuing
2. Core: canvas, size selector, zoom, grid, pixel drawer, keyboard cursor, undo/redo, save/load/new, autosave/autoload, filename field
3. Palette: theme default, select, add/replace/delete, color picker, extraction from loaded image
4. Tools: eyedropper, color pot, shapes
5. Selection: move, copy/cut/paste (system clipboard), flip, rotate, delete
6. Polish: canvas resize with padding, export, screen pipette, live theme change, status bar

## Tools

#### Sidebar
- Size selector 16x16,32x32,64x64,128x128, custom (max 256x256)
- Zoom zoom in and out of the canvas, especially important for bigger canvas
- Grid toggle, shows pixel borders
- Pixel drawer (left click draws a pixel right click removes a pixel, removed pixels are transparent)
- Eyedropper, picks the color of a canvas pixel as current color (also alt+click with any tool)
- Pixel selector, draw a box, all pixels with the box are selected, operations like move, copy, cut, paste, flip, rotate (90° steps only)
- Color pot, color all connected colors which have the same color (similar to paints color pot), only 4-connected (no diagonals)
- Draw shapes: line, rectangle, circle, triangle , hexagon, octagon (holding ctrl keeps the ratio fixed), outline only, pixel-perfect (Bresenham, no anti-aliasing)
- Undo / redo, for every tool

#### Bottom bar
- 10 preselected colors (2 rows of 5)
- Add color button (opens a color picker to add a new color)
- Right click on a color: replace (color picker) or delete
- Screen pipette button in the color picker: pick a color from anywhere on screen (e.g. a reference image in another window) via `hyprpicker`; the panel hides while picking, esc cancels
- Save, load, new and export button
- Filename field, editable
- Status: cursor x,y, current tool, current color

## Canvas
- Transparent pixels are shown as a checkerboard
- Resizing with content: pad (grow) or crop (shrink) evenly on all sides; if the difference is uneven, the extra pixel goes to the right and top

## Files
- Format: PNG
- Default save location ~/Pictures/PixelArt/
- Untitled images are named by timestamp (e.g. `2026-10-10_14-30-05.png`)
- Saving under an existing filename asks before overwriting
- Load: PNGs larger than 256x256 are refused with a message
- Export: PNG scaled up 4x, 8x or 16x with nearest-neighbour (no blur)
- Copy/paste uses the system clipboard (`wl-copy` / `wl-paste`), so selections can be pasted into other apps and images pasted in

## Palette
- New image: the 10 colors come from the current Omarchy theme
- Loading an image: the palette is taken from the image's colors (the 10 most used); if it has fewer, the remaining slots are filled with theme colors
- Add color when all 10 slots are full replaces the selected slot

## Behavior
- Fast and responsive
- Fully keyboard driven operations
- When canvas size is changed also the window size of the plugin changes with it (small size only a small panel, larger size bigger panel)
- Zoom does not change the window size, the canvas scrolls inside the window
- When opened last edited image is automatically loaded
- When closed image is automatically saved; `n` new also saves the current image first
- Omarchy theme change restyles the app live; the palette of the open image stays, the next new image takes the new theme colors

## Keybindings

#### General
- n new
- s save
- o load
- e export
- q quit
- esc cancel selection / shape in progress
- ctrl+z undo
- ctrl+y / ctrl+shift+z redo
- g grid toggle
- +/- zoom

#### Cursor
- arrows move the cursor
- return draw a pixel / set start and end point of a shape or selection
- delete / backspace remove a pixel

#### Tools
- p pixel drawer
- i eyedropper
- b color pot
- v select
- l line
- r rectangle
- c circle
- t triangle
- h hexagon
- shift+o octagon

#### Selection
- ctrl+c copy
- ctrl+x cut
- ctrl+v paste
- f flip horizontal, shift+f flip vertical
- ] rotate 90° clockwise, [ counter-clockwise
- delete remove selected pixels

#### Colors
- numbers 1-0 color select
- a new color (color picker)
- shift+i pick a new color from the screen (pipette)

## Non-goals
Layers, animation frames, brush sizes, symmetry mode, anti-aliasing, filled shapes.

## References:
paint: (main source regarding tools)
https://paint.js.org/

mote: (backend inspiration)
https://github.com/benryanx/mote

style appearcance:
https://github.com/yamz8/omarchy-snake
