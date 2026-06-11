# Changelog

All notable changes to Snipper are documented here. This project follows
[Semantic Versioning](https://semver.org) and the
[Keep a Changelog](https://keepachangelog.com) format.

## [Unreleased]

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

[1.1.0]: https://github.com/v2matosevic/Snipper/releases/tag/v1.1.0
[1.0.0]: https://github.com/v2matosevic/Snipper/releases/tag/v1.0.0
