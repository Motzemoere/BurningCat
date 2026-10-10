# PixelArt

Plugin to make pixel art similar to paint but with only selected features focused on pixel art. Follows the Omarchy color themes

## Platform
- Omarchy 4 shell plugin (`manifest.json`, installed with `omarchy plugin add`)
- `panel` plugin whose editor is a normal Hyprland window (tiled like any app), not a bar popup
- Plugin id: `motzemoere.pixelart`
- Keybind `SUPER + ALT + P` toggles the window: `omarchy-shell shell toggle motzemoere.pixelart`
- The window must receive keyboard input (required for keyboard driven operations)
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
- Size selector 16x16,32x32,64x64,128x128, custom (max 512x512)
- Upscale 2x, 3x or 4x: every pixel becomes a 2x2, 3x3 or 4x4 block (nearest-neighbour), for finer detail work; refused if the result exceeds 512x512
- Zoom zoom in and out of the canvas, especially important for bigger canvas
- Grid toggle, shows pixel borders
- Pixel drawer (left click draws a pixel right click removes a pixel, removed pixels are transparent); pen size 1x1, 2x2, 4x4 or 8x8, the cursor is the top-left pixel of the block; the eraser uses the same size
- Options of the active tool (pen sizes, selection flip/rotate) appear below the sidebar
- Eyedropper, picks the color of a canvas pixel as current color (also alt+click with any tool)
- Pixel selector, draw a box, all pixels with the box are selected, operations like move, copy, cut, paste, flip, rotate (90° steps only)
- Color pot, color all connected colors which have the same color (similar to paints color pot), only 4-connected (no diagonals)
- Draw shapes: line, rectangle, circle, triangle , hexagon, octagon (holding ctrl keeps the ratio fixed), outline only, pixel-perfect (Bresenham, no anti-aliasing)
- Undo / redo, for every tool

#### Bottom bar
- 20 preselected colors (2 rows of 10), plus 2 extra slots in front of them, set slightly apart; they default to black and white and keep their colors when a new image is made or one is loaded
- Add color button (opens a color picker to add a new color); the picker has HSV, RGB and HSL modes
- Right click on a color: replace (color picker) or delete
- Screen pipette button in the color picker: pick a color from anywhere on screen (e.g. a reference image in another window) via `hyprpicker`; esc cancels
- Save, save as, load, new and export button
- Filename field, editable
- Status: cursor x,y, current tool, current color

## Canvas
- Transparent pixels are shown as a checkerboard, or a black, white or light grey background, picked from the Background swatches (screen only, not saved)
- The mouse pointer is hidden over the canvas; the one-pixel cell outline is the cursor
- Resizing with content: pad (grow) or crop (shrink) evenly on all sides; if the difference is uneven, the extra pixel goes to the right and top

## Files
- Format: PNG
- Default save location ~/Pictures/PixelArt/
- Untitled images are named by timestamp (e.g. `2026-10-10_14-30-05.png`)
- Saving under an existing filename asks before overwriting
- Load: PNGs larger than 512x512 are refused with a message
- Export: PNG scaled up 4x, 8x or 16x with nearest-neighbour (no blur); background transparent, grey, white or the current color (save always keeps transparency)
- Copy/paste uses the system clipboard (`wl-copy` / `wl-paste`), so selections can be pasted into other apps and images pasted in

## Palette
- New image: the 10 colors come from the current Omarchy theme
- Loading an image: the palette is taken from the image's colors (the 20 most used); if it has fewer, the remaining slots are filled with theme colors
- Add color when all 22 slots (including the extra two) are full replaces the selected slot

## Behavior
- Fast and responsive
- Fully keyboard driven operations
- The canvas fills the window; changing canvas size refits the zoom to the window
- Zoom does not change the window size, the canvas scrolls inside the window
- When opened last edited image is automatically loaded
- When closed image is automatically saved; `n` new also saves the current image first
- Omarchy theme change restyles the app live; the palette of the open image stays, the next new image takes the new theme colors

## Keybindings

The single-key bindings below are defaults: `shift+k` opens a keybinding menu where you select an action, press enter, then press the new key (taking a key in use swaps the two bindings; `shift+r` resets all). Arrows, space, esc, delete/backspace, ctrl combinations and the number keys are fixed.

#### General
- n new
- s save
- ctrl+s save as (focuses the filename field; enter saves under the typed name)
- o load
- e export
- shift+k keybinding menu
- u upscale
- q quit
- esc cancel selection / shape in progress
- ctrl+z undo
- ctrl+y / ctrl+shift+z redo
- g grid toggle
- k background swatches (checkerboard, black, white, grey); k again cycles, esc closes
- +/- zoom

#### Cursor
- arrows move the cursor, ctrl+arrows move it and scroll the view by one pixel, so the image slides under the cursor when zoomed in
- space draw a pixel / set start and end point of a shape or selection (ctrl+space keeps the ratio)
- c / delete / backspace remove a pixel (or the selected pixels; with the color pot, all connected pixels of that color)

#### Tools
- p pixel drawer; p again cycles the pen size up, shift+p down
- i eyedropper
- b color pot
- v select
- l line
- r rectangle
- shift+c circle
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
- numbers 1-0 select colors 1-10, shift+1-0 colors 11-20
- z / x select the extra colors 21 / 22
- a new color (color picker)
- shift+i pick a new color from the screen (pipette)

## Non-goals
Layers, animation frames, symmetry mode, anti-aliasing, filled shapes.

## References:
paint: (main source regarding tools)
https://paint.js.org/

mote: (backend inspiration)
https://github.com/benryanx/mote

style appearcance:
https://github.com/yamz8/omarchy-snake
