<p align="center">
  <img src="docs/media/orbitdrop-icon.png" alt="OrbitDrop" width="96" height="96">
</p>

<p align="center">
  <strong>OrbitDrop</strong><br>
  <sub>A floating action wheel for your files: drag an image or PDF, drop it on what you want done</sub>
</p>

<p align="center">
  <a href="https://github.com/markadebartolo/OrbitDrop/releases/latest"><strong>Download for Mac</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/markadebartolo/OrbitDrop/releases">All releases</a>
</p>

---

## Why OrbitDrop

Converting a screenshot, cropping a photo or pulling the text out of a PDF usually means opening an app,
finding the file, exporting, and naming the result. OrbitDrop puts those actions in a small wheel that
appears where you are already working. Drop a file on a sector and the result is saved beside a copy of
the original. Everything runs on your Mac: no account, no network calls, no third-party code.

## Features

- **Convert** between PNG, JPG, HEIC, TIFF, BMP and PDF. WebP and AVIF appear when your Mac can write them.
- **PDF to images**: every page becomes its own numbered image.
- **Text out of anything**: TXT or an editable DOCX from a PDF's text, with on-device OCR for scans and photos.
- **Crop** by dragging, by aspect ratio or by exact pixel size.
- **Add a background**: color and gradient presets, padding, rounded corners, shadow, and 1:1, 16:9 or 4:3 canvases.
- **Compress** to a JPEG quality and a longest edge, never upscaling.
- **Edit** brightness, contrast, saturation and rotation.
- **Annotate** with text labels and outline rectangles.
- **Redact** by replacing the selected pixels with solid black in a new flattened image.
- **Metadata**: see what an image or PDF carries, and save a clean copy without EXIF or GPS data.
- **Nothing is overwritten.** Every action makes a timestamped folder with a `Before` copy of each source and the results in `After`.
- **Menu bar only**: no Dock icon and no background services.

## Get started

1. Download **OrbitDrop-macos.zip** from [Releases](https://github.com/markadebartolo/OrbitDrop/releases/latest) and unzip it.
2. Move **OrbitDrop.app** to your Applications folder and open it.
3. Click the orbit icon in the menu bar, then **Choose files…** or **Show action wheel**.
4. Drop a file on a sector, or press its number key.
5. Find the result in `~/Documents/OrbitDrop`, in the newest folder, under `After`.

### Who can use the download

| | |
|--|--|
| **Works on** | Apple Silicon and Intel Macs · macOS 13 Ventura or later |
| **File** | `OrbitDrop-macos.zip`, a universal build |
| **Signed** | Developer ID, notarized by Apple |

## Using the wheel

| Key or action | What it does |
|--|--|
| **Tab** | Switches the wheel between converting and editing tools |
| **Arrow keys, Return** | Select an action and run it |
| **Number keys** | Pick a sector, counting clockwise from the top |
| **Escape** | Closes the wheel |
| **Center of the wheel** | Switches wheels when files are loaded; opens the file chooser when none are |
| **Option (⌥) while dragging** | Switches to the editing tools |

**Show wheel while dragging files** in the menu makes the wheel appear by itself when you start dragging a
file in Finder. It is off until you turn it on. **Open With → OrbitDrop** in Finder works as well.

Use **History folder → Choose folder…** to keep results somewhere other than `~/Documents/OrbitDrop`.

## Limits worth knowing

- Editing tools work on one file at a time. For a PDF you choose the page to export as an image; OrbitDrop does not rewrite or redact a whole PDF.
- DOCX export keeps the text, not the original layout, columns or tables. OCR can make mistakes, so read its output.
- Animated and multi-frame images use their first frame. Video, audio and folders are not handled.
- Images are limited to 64 megapixels and 16,000 pixels on a side. PDF pages are rendered at about 144 dpi.
- Compressing an image that is already well compressed may not make it smaller.

## Build from source

You need macOS 13 or later and Apple's Command Line Tools (`xcode-select --install`). No Xcode project and
no packages are required.

```bash
bash scripts/build.sh
open build/OrbitDrop.app
```

The build compiles the app, draws its icon, signs it for local use and runs the self-test: checks of
decoding, cropping, resizing, rotation, redaction, PDF conversion, DOCX structure, name collisions and
wheel hit testing against the real macOS frameworks. `bash scripts/validate.sh` repeats that from a clean
folder and inspects the finished bundle. `Tests/Mac-acceptance.md` lists what is checked by hand.

`Install.command` builds the app and puts it in `~/Applications` in one step.

**Sign and notarize** with your own Developer ID:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="your-profile" bash scripts/release.sh
```

That makes `dist/OrbitDrop-macos.zip`, a universal build, stapled and ready to attach to a release.

## How it is put together

Swift and AppKit only, in `Sources/OrbitDrop`:

| File | What it holds |
|--|--|
| `AppDelegate.swift` | The menu bar item, drag detection, choosing files, where results go |
| `Wheel.swift` | The translucent wheel, its drop targets, keyboard control and accessibility labels |
| `Canvas.swift` | Crop selection and the annotate and redact interactions |
| `Editor.swift` | The editing windows and their controls |
| `ImageEngine.swift` | Rendering, conversion, OCR, image effects and collision-safe saving |
| `OutputStore.swift` | The timestamped `Before` and `After` folders |
| `DocxWriter.swift` | DOCX files written without any library |
| `SelfTest.swift` | The checks the build runs |

## Remove it

Quit OrbitDrop from its menu and move the app to the Trash. It installs no launch agents, Finder
extensions or background services. Your results stay in `~/Documents/OrbitDrop` until you delete them.

---

<p align="center">
  <sub>Menu bar · On-device only · Originals always kept</sub>
</p>
