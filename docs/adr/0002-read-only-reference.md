# The second image is a read-only Reference, not a second editable Image

Showing two images side by side was wanted for copying pixel groups between them.
We made the second one a read-only Reference (select, copy, eyedropper, zoom)
instead of a second editable Image, because editing both would need a second
undo history, unsaved-changes handling and save-on-close for two files. The
transfer reuses the system clipboard copy and paste.
