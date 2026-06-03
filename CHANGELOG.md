# Changelog

All notable changes to Snipper are documented here. This project follows
[Semantic Versioning](https://semver.org) and the
[Keep a Changelog](https://keepachangelog.com) format.

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

[1.0.0]: https://github.com/v2matosevic/Snipper/releases/tag/v1.0.0
