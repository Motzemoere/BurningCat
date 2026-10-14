# BurningCat

A keyboard-driven pixel art editor for Omarchy.

## Language

**Image**:
The one picture being edited, with its own undo history and file.
_Avoid_: Document, canvas, file

**Selection**:
The pixels picked for moving, copying or transforming. It floats above the Image once moved or transformed, until committed.
_Avoid_: Marquee, region

**Magic wand**:
The tool that selects the Object under the clicked pixel instead of a dragged rectangle.
_Avoid_: Wand select, object select, freeform selection

**Object**:
A connected outline of one color plus every pixel it encloses; the unit the Magic wand selects.
_Avoid_: Shape, blob, region

**Reference**:
A second picture shown beside the Image, read-only, that you can select and copy from.
_Avoid_: Second image, source, pane
