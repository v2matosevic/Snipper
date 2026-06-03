# Snipper

A tiny macOS menu-bar app that brings the Windows **Win+Shift+S** snipping
experience to the Mac: press **⇧⌥S** (Shift-Option-S) anywhere, drag to select a
region of the screen, and the snip lands on your clipboard **and** in
`~/Pictures/Snipper`. A floating preview fades in at the bottom-right corner
(just like macOS's own screenshots) — click it to open the capture, or ignore
it and it fades away on its own.

It wraps macOS's own `screencapture` tool, so the selection UI is the native
crosshair (drag a region, or press **Space** to grab a whole window).

## Build

Needs only the Xcode **Command Line Tools** (no full Xcode):

```sh
./build.sh
open Snipper.app
```

`build.sh` compiles a release binary with Swift Package Manager, wraps it in a
`Snipper.app` bundle (menu-bar–only, no Dock icon), and ad-hoc code-signs it.

## First run — grant Screen Recording

macOS requires Screen Recording permission for *any* screen capture. The first
time you press ⇧⌥S, Snipper adds itself to the list and points you at:

**System Settings → Privacy & Security → Screen Recording → enable Snipper**

Then press ⇧⌥S again. (Toggling the permission may ask you to quit & reopen the
app — that's macOS, not Snipper.)

## Use

- **⇧⌥S** — capture a selection. Drag a box, or hit **Space** then click a window.
  **Esc** cancels.
- A preview fades in at the bottom-right: **click** it to open the snip, **hover**
  to keep it on screen, **✕** to dismiss. Otherwise it auto-dismisses after 5s.
- Menu-bar icon → choose where snips go: **Clipboard + Folder** (default),
  **Clipboard only**, or **Folder only**.
- **Open Save Folder** reveals `~/Pictures/Snipper`.
- **Launch at Login** keeps it running across reboots.

## Rebind the shortcut

Edit the two constants at the top of
[`Sources/Snipper/AppDelegate.swift`](Sources/Snipper/AppDelegate.swift) and
rebuild:

```swift
private let keyCode   = UInt32(kVK_ANSI_S)            // any kVK_ANSI_* key code
private let modifiers = UInt32(shiftKey | optionKey)  // Carbon modifier flags
```

## How it works

| Piece | Role |
|-------|------|
| `HotKey.swift` | System-wide ⇧⌥S via Carbon `RegisterEventHotKey` — no Accessibility permission required. |
| `ScreenshotService.swift` | Runs `screencapture -i -o` to a temp file, then routes it to clipboard and/or `~/Pictures/Snipper`. |
| `ThumbnailController.swift` | The bottom-right floating preview: a borderless `NSPanel` that fades in, auto-dismisses, and opens the file on click. |
| `AppDelegate.swift` | Menu-bar item, destination toggles, permission prompt, launch-at-login. |

## Notes / limitations

- The ad-hoc signature changes on each `./build.sh`, which can make macOS
  re-ask for Screen Recording after a rebuild. For a stable identity, sign with
  a self-signed or Developer ID certificate instead of `--sign -`.
- `Launch at Login` records the app's current path; move `Snipper.app` and
  you'll need to toggle it off/on again.
- macOS already has a built-in equivalent (System Settings → Keyboard →
  Keyboard Shortcuts → Screenshots → *Copy picture of selected area to
  clipboard*) you can rebind to ⇧⌥S with zero code — Snipper adds the
  save-to-folder + clipboard combo and a menu-bar home.
