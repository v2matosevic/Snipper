import AppKit
import Carbon.HIToolbox
import CoreGraphics
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ── Shortcut ──────────────────────────────────────────────────────────
    // ⇧⌥S. To rebind, change these two constants (key codes are `kVK_ANSI_*`,
    // modifiers are Carbon flags: shiftKey / optionKey / controlKey / cmdKey).
    private let keyCode = UInt32(kVK_ANSI_S)
    private let modifiers = UInt32(shiftKey | optionKey)
    // ──────────────────────────────────────────────────────────────────────

    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let screenshots = ScreenshotService()
    private let thumbnail = ThumbnailController()

    private var destinationItems: [(item: NSMenuItem, value: ScreenshotService.Destination)] = []
    private var loginItem: NSMenuItem?

    private let defaultsKey = "destination"

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreDestination()
        buildStatusItem()
        registerHotKey()
        screenshots.onCapture = { [weak self] result in
            self?.thumbnail.show(image: result.image,
                                 fileURL: result.url,
                                 isTemporary: result.isTemporary)
        }

    }

    // MARK: - Hotkey

    private func registerHotKey() {
        hotKey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.capture()
        }
        if hotKey == nil {
            NSLog("Snipper: failed to register ⇧⌥S (already claimed by another app?)")
        }
    }

    @objc private func capture() {
        // Run screencapture directly. The act of capturing is what registers
        // Snipper in the Screen Recording list and triggers the OS prompt — a
        // CGPreflight gate here just blocks before that can happen.
        screenshots.captureInteractive()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("camera.viewfinder")

        let menu = NSMenu()

        let capture = NSMenuItem(title: "Capture Selection", action: #selector(capture), keyEquivalent: "s")
        capture.keyEquivalentModifierMask = [.shift, .option]
        capture.target = self
        menu.addItem(capture)

        menu.addItem(.separator())
        menu.addItem(destinationItem("Clipboard + Folder", .both))
        menu.addItem(destinationItem("Clipboard only", .clipboardOnly))
        menu.addItem(destinationItem("Folder only", .folderOnly))
        refreshDestinationStates()

        menu.addItem(.separator())

        let reveal = NSMenuItem(title: "Open Save Folder", action: #selector(openFolder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        loginItem = login
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Snipper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func destinationItem(_ title: String, _ value: ScreenshotService.Destination) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(setDestination(_:)), keyEquivalent: "")
        item.target = self
        item.tag = value.rawValue
        destinationItems.append((item, value))
        return item
    }

    @objc private func setDestination(_ sender: NSMenuItem) {
        guard let value = ScreenshotService.Destination(rawValue: sender.tag) else { return }
        screenshots.destination = value
        UserDefaults.standard.set(value.rawValue, forKey: defaultsKey)
        refreshDestinationStates()
    }

    private func refreshDestinationStates() {
        for (item, value) in destinationItems {
            item.state = (value == screenshots.destination) ? .on : .off
        }
    }

    private func restoreDestination() {
        let raw = UserDefaults.standard.integer(forKey: defaultsKey) // missing → 0 → .both
        if let value = ScreenshotService.Destination(rawValue: raw) {
            screenshots.destination = value
        }
    }

    @objc private func openFolder() {
        let dir = screenshots.saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Snipper: launch-at-login toggle failed: \(error)")
        }
        loginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Status icon feedback

    private func setIcon(_ symbol: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Snipper")
    }
}
