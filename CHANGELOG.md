# Changelog

All notable changes to Snipper are documented here. This project follows
[Semantic Versioning](https://semver.org) and the
[Keep a Changelog](https://keepachangelog.com) format.

## [1.3.0] — 2026-07-02

### Added
- **Screen recording** — press **⇧⌥D** and select like a screenshot: drag a
  region, or press **Space** and click a window (the desktop counts, so
  that's full screen); **Esc** cancels. The selection UI is Snipper's own
  overlay — macOS refuses `screencapture -v -i` ("video not valid with -i"),
  so interactive video selection has to be ours — and the chosen rect is
  recorded natively via `screencapture -v -R`, meaning no new permissions.
  Press **⇧⌥D** again (or the menu-bar item) to stop — the icon turns into a
  red stop button while recording. Saved next to the snips as
  `Recording <timestamp>.mov`, with the file's URL on the clipboard, and the
  corner preview (with a play badge) works as usual: drag it out, or click
  to edit. Recordings show mouse clicks, since demos and bug repros are the
  point.
- **System audio in recordings** (menu: **Record System Audio**, on by
  default) — captures what's playing (a browser video, a call, an app's
  sound) alongside the picture via `screencapture -A`. First use may show
  macOS's one-time audio-recording consent. DRM-protected players (Netflix
  and friends) black out their pixels for every screen recorder — that's OS
  enforcement, not a Snipper limitation.
- **Trim editor** for recordings — clicking a recording's preview opens a
  player with QuickTime's native trim UI. Confirming a trim re-exports the
  kept range losslessly (no re-encode) and overwrites the file in place;
  **Copy File** / **Copy Path** buttons match the markup editor's habits.
- **30-day auto-delete** — captures are meant to be temporary, so Snipper now
  sweeps `~/Pictures/Snipper` at launch and twice a day, deleting its own
  `Snip *.png` / `Recording *.mov` files older than 30 days. Files you put
  there yourself are never touched. Tune or disable without rebuilding:
  `defaults write com.version2.snipper retentionDays -int 90` (≤ 0 disables).

## [1.2.0] — 2026-06-12

### Added
- **Blur tool** in the markup editor — drag a rectangle to pixelate sensitive
  areas (tokens, emails, customer data) before sharing. Identical on screen and
  in the exported PNG.
- **Step badges** in the markup editor — click to drop numbered circles
  (1, 2, 3…); drag to fine-position. Undoing a badge renumbers the rest, since
  numbers derive from order.

- **Copy Text (OCR)** button in the editor — on-device Vision text recognition
  puts the snip's text (error dialogs, logs) on the clipboard.
- **Copy Path** button in the editor (file-backed snips) — copies the PNG's
  path for CLI/AI prompts.
- The corner preview is now a **drag source** — drag the snip out and drop it
  into a chat input, terminal, or Finder.

### Changed
- Clicking the corner preview now opens the **markup editor** instead of the
  default image viewer — the pencil button still works too. The file itself is
  one click away via **Open Save Folder**.

## [1.1.0] — 2026-06-03

### Added
- **Markup editor** for a fresh capture: hover the corner preview and click the
  pencil to annotate with **rectangles, ellipses, freehand strokes, and arrows**,
  with adjustable color and stroke width. **Undo** with ⌘Z; **Copy** (Return)
  puts the annotated image on the clipboard, or **Save** overwrites the saved
  PNG. Annotations are rendered at the snip's full pixel resolution, so a Retina
  capture stays sharp.

## [1.0.0] — 2026-06-03

First public release.

### Added
- Global **⇧⌥S** hotkey (Carbon `RegisterEventHotKey`, no Accessibility
  permission) to start a capture from any app.
- Native crosshair region selection via macOS `screencapture` — drag a region,
  or press **Space** to grab a whole window; **Esc** cancels.
- Captures are copied to the clipboard **and** saved to `~/Pictures/Snipper`,
  with a menu toggle for **Clipboard + Folder** / **Clipboard only** /
  **Folder only**.
- Floating bottom-right preview that fades in, auto-dismisses after ~5s, can be
  kept on hover, dismissed with ✕, and opens the capture on click.
- Silent capture (no shutter sound).
- Menu-bar–only app (no Dock icon): destination toggles, **Open Save Folder**,
  **Launch at Login**, **Quit**.
- App icon (a selection-bracket mark on a slate squircle), generated
  reproducibly from `icon/make-icon.swift`.
- One-time stable self-signed code-signing setup (`trust-cert.sh`) so the macOS
  Screen Recording grant persists across rebuilds; `build.sh` falls back to
  ad-hoc signing when it isn't set up.
- GitHub Actions workflow that builds on macOS and publishes a zipped build to
  Releases on a `v*` tag (manual runs upload an artifact).

[1.3.0]: https://github.com/v2matosevic/Snipper/releases/tag/v1.3.0
[1.2.0]: https://github.com/v2matosevic/Snipper/releases/tag/v1.2.0
[1.1.0]: https://github.com/v2matosevic/Snipper/releases/tag/v1.1.0
[1.0.0]: https://github.com/v2matosevic/Snipper/releases/tag/v1.0.0
