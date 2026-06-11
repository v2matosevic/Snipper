# Snipper

A tiny macOS menu-bar app that brings the Windows **Win + Shift + S** snipping
experience to the Mac. Press **⇧⌥S** (Shift-Option-S) anywhere, drag to select a
region, and the snip is copied to your clipboard **and** saved to
`~/Pictures/Snipper`. A floating preview fades in at the bottom-right corner —
just like macOS's own screenshots — which you can click to open or simply ignore.

Under the hood it drives macOS's native `screencapture`, so the selection UI is
the familiar crosshair (drag a region, or press **Space** to grab a whole window).

## Features

- **⇧⌥S** global shortcut — works in any app, and is rebindable.
- Native crosshair region select, or **Space** to capture a whole window.
- Copies to the clipboard **and** saves a timestamped PNG — or either on its own.
- Floating bottom-right preview: click to mark up, hover to keep, ✕ to dismiss.
- **Markup editor** — click the preview (or its pencil) to draw rectangles,
  ellipses, freehand, arrows, **blur out sensitive areas**, and drop
  **numbered step badges** (1, 2, 3… — perfect for "click here, then here"
  bug reports and AI prompts); then **Copy** the annotated image or **Save**
  over the PNG.
- Silent capture — no shutter sound.
- Menu-bar only: no Dock icon, no window clutter.
- Optional launch at login.

## Requirements

- macOS 13 (Ventura) or later.
- Xcode **Command Line Tools** with a Swift 5.9+ toolchain
  (`xcode-select --install`) — full Xcode not needed.

## Install

### Download a build

Grab the latest zip from
[**Releases**](https://github.com/v2matosevic/Snipper/releases), unzip, and move
**Snipper.app** to `/Applications`. These builds are ad-hoc signed (no Apple
Developer ID, not notarized), so macOS Gatekeeper warns on first launch — either
right-click **Snipper.app** → **Open** → **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Snipper.app
```

### Build from source

```sh
git clone https://github.com/v2matosevic/Snipper.git
cd Snipper
./trust-cert.sh   # one-time, recommended — stable signing (see below)
./build.sh
open Snipper.app
```

Building from source keeps the app stably signed (no Gatekeeper warning) and is the
better path if you'll tweak it. To keep it around, drag `Snipper.app` into
`/Applications` and turn on **Launch at Login** from its menu.

## Stable signing — run once (recommended)

```sh
./trust-cert.sh
```

`screencapture` needs macOS **Screen Recording** permission, and macOS ties that
grant to the app's code signature. An ad-hoc signature changes on every build, so
the grant would be lost each time you rebuild. `trust-cert.sh` creates and trusts a
self-signed code-signing identity in its own throwaway keychain (your login
keychain is untouched; macOS asks for your password once). After that, `build.sh`
signs with it and the permission persists across rebuilds. Skip it and the build
still works ad-hoc — you'll just have to re-grant Screen Recording after each build.

## First run — grant Screen Recording

The Screen Recording list has **no manual "+"** — an app only appears there once it
actually captures. So:

1. Press **⇧⌥S** and drag a selection. macOS registers Snipper and prompts.
2. Enable **Snipper** in System Settings → Privacy & Security → **Screen Recording**.
3. Quit & reopen Snipper (a running process can't see a fresh grant). Done.

## Usage

- **⇧⌥S** — capture a selection. Drag a box, or press **Space** then click a window.
  **Esc** cancels.
- The bottom-right preview: **click** to open the snip in the markup editor,
  **hover** to keep it on screen, **✕** to dismiss. It auto-dismisses after
  about 5 seconds.
- Menu-bar icon → pick a destination: **Clipboard + Folder** (default),
  **Clipboard only**, or **Folder only**.
- **Open Save Folder** reveals `~/Pictures/Snipper`.
- **Launch at Login** keeps Snipper running across reboots.

## Rebind the shortcut

Edit the two constants at the top of `Sources/Snipper/AppDelegate.swift`, then rebuild:

```swift
private let keyCode   = UInt32(kVK_ANSI_S)            // any kVK_ANSI_* key code
private let modifiers = UInt32(shiftKey | optionKey)  // Carbon modifier flags
```

## How it works

| File | Role |
|------|------|
| `HotKey.swift` | System-wide ⇧⌥S via Carbon `RegisterEventHotKey` — no Accessibility permission required. |
| `ScreenshotService.swift` | Runs `screencapture -i -o -x` (silent) to a temp file, then routes it to the clipboard and/or `~/Pictures/Snipper`. |
| `ThumbnailController.swift` | The bottom-right floating preview — a borderless `NSPanel` that fades in, auto-dismisses, and opens the capture on click. |
| `AppDelegate.swift` | Menu-bar item, destination toggles, the ⇧⌥S hotkey, launch at login. |

Snipper captures through the `screencapture` tool rather than in-process, so it has
no preflight permission gate — performing a capture is what registers it with macOS
and triggers the Screen Recording prompt.

## License

MIT — see [LICENSE](LICENSE).

---

Built by **[Version2](https://github.com/v2matosevic)**.
