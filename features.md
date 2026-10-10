# PixelArt

Plugin to make pixel art similar to paint but with only selected features focused on pixel art. Follows the Omarchy color themes

## Tools

#### Sidebar
- Size selector 16x16,32x32,64x64,128x128, custom
- Zoom zoom in and out of the canvas, especially important for bigger canvas
- Pixel drawer (left click draws a pixel right click removes a pixel)
- Pixel selector, draw a box, all pixels with the box are selected, operations like move, copy, cut, paste, flip, rotate 
- Color pot, color all connected colors which have the same color (similar to paints color pot)
- Draw shapes: line, rectangle, circle, triangle , hexagon, octagon (holding ctrl keeps the ratio fixed)

#### Bottom bar
- 10 preselected colors (2 rows of 5)
- Add color button (opens a color picker to add a new color)
- Save, load and new button
- Filename field, editable

## Behavior
- Fast and responsive
- If possible also fully keyboard driven operations
- Default save location ~/Pictures/PixelArt/
- When canvas size is changed also the window size of the plugin changes with it (small size only a small panel, larger size bigger panel)
- When opened last edited image is automatically loaded
- When closed image is automatically saved

## Suggested keyboindings

- n new
- esc quit
- return draw a pixel
- numbers 1-0 color select 
- ß new color (color selector)
- s save

## References:
paint: (main source regarding tools)
https://paint.js.org/

mote: (backend inspiration)
https://github.com/benryanx/mote

style appearcance:
https://github.com/yamz8/omarchy-snake


