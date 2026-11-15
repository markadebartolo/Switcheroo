# Mac acceptance checks

These are checked by hand on a Mac. The automated checks in `scripts/build.sh` do not cover them.

1. Run `Install.command`. Verify compilation, app signing, all self-tests, and first-launch instructions.
2. Drag a PDF in Finder. Verify the wheel appears once, stays fixed near the starting cursor location, and disappears after a canceled drag.
3. Drop a multi-page PDF on JPG. Verify one image per page, correct orientation, and the original PDF is unchanged.
4. Drag an image. Hold and release Option; verify that the wheel switches between formats and editing actions before the drop.
5. Drop onto Crop. Draw and move a selection; resize all four corners; check presets and width/height input against the actual saved PNG dimensions.
6. Add a background to that crop. Exercise every swatch and slider; compare Auto, square, 16:9, and 4:3 previews to saved PNG files.
7. Compress an image at two quality levels and two dimensions. Verify no upscaling and correct white replacement of transparent pixels.
8. Test brightness, contrast, saturation, and all four rotations. Compare the exported image with the preview.
9. Add text and outline annotations; undo; save. Redact a separate copy and verify the exported pixels are black at the expected coordinates.
10. Inspect metadata of an image with EXIF/GPS; save a clean PNG; verify those source metadata fields are absent.
11. Convert text PDFs, scanned PDFs, and photos of text into TXT and DOCX; open DOCX in Word or Pages and review extracted text.
12. Use a PDF page selector in each editor; confirm the output contains only the chosen page with the correct page suffix.
13. Convert two files in one batch; repeat the conversion; ensure previous outputs and source files remain intact.
14. Select a custom output folder. Try saving from a read-only source location, and verify useful error handling when the destination is not writable.
15. Test light and dark appearance, Retina displays, multiple monitors, Spaces, and a fullscreen app. Check that wheel sectors and controls remain visible and reachable near screen edges.
16. Test file chooser mode, Open With, Tab, Escape, number keys, arrow/Return selection, and VoiceOver action labels.
17. Quit the app and confirm the menu icon and event monitor disappear. Relaunch and confirm saved output-folder and automatic-drag settings persist.
