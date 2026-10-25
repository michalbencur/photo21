# Photo21

A tiny macOS app for one thing: crop and rotate a batch of photos, fast, and write them back where they came from.

- Open photos or folders (File ▸ Open, drop on the window, drop on the Dock icon, Finder "Open With", `open -a Photo21 *.jpg`).
- Step through them one by one. Pick an aspect ratio from the hard-coded list (`Photo21/Model/AspectRatio.swift`), straighten by any angle, hit **Return**.
- Saving overwrites the file in place; the untouched original goes to the **Trash** first. EXIF/GPS/XMP and the colour profile are kept, orientation is normalised.
- Formats ImageIO can write (JPEG, HEIC, PNG, TIFF…) keep their format. Anything else (RAW) is written as a `.jpg` next to the original, which stays untouched.

## Keyboard

| Action | Key |
|---|---|
| Save & Next | Return, ⌘S |
| Save Copy & Next (`name-1.ext`) | ⇧⌘S |
| Skip / Previous | ⌘→ / ⌘← |
| Aspect ratio | ⌘0 … ⌘8 (sticky across photos) |
| Swap landscape / portrait | ⌘/ |
| Flip horizontal | ⇧⌘F |
| Rotate 90° CW / CCW | ⌘R / ⇧⌘R |
| Straighten | drag the dial, double-click it to reset, ← → (0.1°, ⇧ for 1°) |
| Straighten to 0° | ⇧⌘0 |
| Reset edits | ⌘⌫ |
| Open… | ⌘O |

## Building

With Xcode (after accepting the licence once with `sudo xcodebuild -license accept`):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Photo21.xcodeproj -scheme Photo21 -configuration Release -derivedDataPath build build
xcodebuild -project Photo21.xcodeproj -scheme Photo21 test
```

Without xcodebuild (plain `swiftc`, ad-hoc signed, works today):

```sh
Scripts/build.sh                      # -> build/manual/Photo21.app
cp -R build/manual/Photo21.app /Applications/
```

Tests can also run through SwiftPM using the Xcode macro plugins; see `Scripts/test.sh`.

## Design notes

- Swift 6 (strict concurrency), SwiftUI, macOS 15+, no dependencies, no sandbox.
- Decoding and encoding via ImageIO. The UI works on a ≤2560 px orientation-baked preview; the full-resolution image is decoded only when saving, on a background task, while the UI already shows the next photo.
- Rotate + crop is one Core Graphics draw into a context the size of the crop (`Photo21/Imaging/Renderer.swift`), in the source colour space. Angle 0 is a pixel-exact `CGImage.cropping`.
- Model: the crop rect lives in the canvas of the rotated image and is always kept inside the rotated image polygon (`Photo21/Imaging/Geometry.swift`), so no empty corners can ever appear.
- The `.xcodeproj` is hand-written and uses Xcode 16 synchronized folders: add files by creating them, no project edits needed.
