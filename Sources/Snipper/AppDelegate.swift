import AppKit
import Carbon.HIToolbox
import CoreGraphics
import ServiceManagement

/// What the two post-capture editors (markup for stills, trim for movies)
/// have in common, so the delegate can host either behind one window dance.
protocol EditorWindowController: AnyObject {
    var onClose: (() -> Void)? { get set }
    func present()
}

extension AnnotationEditorWindowController: EditorWindowController {}
extension TrimEditorWindowController: EditorWindowController {}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ── Shortcuts ─────────────────────────────────────────────────────────
    // ⇧⌥S snips, ⇧⌥D records (press again to stop). To rebind, change these
    // constants (key codes are `kVK_ANSI_*`, modifiers are Carbon flags:
    // shiftKey / optionKey / controlKey / cmdKey).
    private let keyCode = UInt32(kVK_ANSI_S)
    private let recordKeyCode = UInt32(kVK_ANSI_D)
    private let modifiers = UInt32(shiftKey | optionKey)
    // ──────────────────────────────────────────────────────────────────────

    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var recordHotKey: HotKey?
    private let screenshots = ScreenshotService()
    private lazy var recorder = RecordingService(saveDirectory: screenshots.saveDirectory)
    private lazy var retention = RetentionService(directory: screenshots.saveDirectory)
    private let thumbnail = ThumbnailController()
    private var editors: [EditorWindowController] = []

    private var destinationItems: [(item: NSMenuItem, value: ScreenshotService.Destination)] = []
    private var loginItem: NSMenuItem?
    private var recordItem: NSMenuItem?
    private var audioItem: NSMenuItem?

    private let defaultsKey = "destination"
    private let audioDefaultsKey = "recordSystemAudio"

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreDestination()
        buildStatusItem()
        registerHotKey()
        retention.start()
        screenshots.onCapture = { [weak self] result in
            self?.thumbnail.show(image: result.image,
                                 fileURL: result.url,
                                 isTemporary: result.isTemporary)
        }
        recorder.onCapture = { [weak self] result in
            self?.thumbnail.show(image: result.poster,
                                 fileURL: result.url,
                                 isTemporary: false)
        }
        recorder.onStateChange = { [weak self] recording in
            self?.recordingStateChanged(recording)
        }
        thumbnail.onEdit = { [weak self] url, isTemporary in
            self?.openEditor(url: url, isTemporary: isTemporary)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't orphan a live recording: stop it and salvage the movie.
        recorder.shutdown()
    }

    // MARK: - Markup editor

    private func openEditor(url: URL, isTemporary: Bool) {
        let opened: EditorWindowController? = url.pathExtension.lowercased() == "mov"
            ? TrimEditorWindowController(url: url)
            : AnnotationEditorWindowController(url: url, isTemporary: isTemporary)
        guard let controller = opened else {
            NSLog("Snipper: couldn't open the editor for \(url.lastPathComponent)")
            return
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.editors.removeAll { $0 === controller }
            // Back to a menu-bar agent only once the last editor is gone.
            if self.editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
        // Become a regular (focusable) app while any editor is open. Multiple
        // editors are allowed — each is retained here until its own window closes.
        if editors.isEmpty { NSApp.setActivationPolicy(.regular) }
        editors.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.present()
    }

    // MARK: - Hotkey

    private func registerHotKey() {
        hotKey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.capture()
        }
        if hotKey == nil {
            NSLog("Snipper: failed to register ⇧⌥S (already claimed by another app?)")
        }
        recordHotKey = HotKey(keyCode: recordKeyCode, modifiers: modifiers) { [weak self] in
            self?.toggleRecording()
        }
        if recordHotKey == nil {
            NSLog("Snipper: failed to register ⇧⌥D (already claimed by another app?)")
        }
    }

    @objc private func capture() {
        // Run screencapture directly. The act of capturing is what registers
        // Snipper in the Screen Recording list and triggers the OS prompt — a
        // CGPreflight gate here just blocks before that can happen.
        screenshots.captureInteractive()
    }

    @objc private func toggleRecording() {
        recorder.toggle()
    }

    @objc private func toggleAudio() {
        recorder.capturesAudio.toggle()
        UserDefaults.standard.set(recorder.capturesAudio, forKey: audioDefaultsKey)
        audioItem?.state = recorder.capturesAudio ? .on : .off
    }

    /// Flip the menu bar into (and out of) "recording" dress: red stop icon,
    /// menu item retitled — both so it's obvious a recording is live and how
    /// to end it.
    private func recordingStateChanged(_ recording: Bool) {
        if recording {
            setIcon("stop.circle.fill")
            statusItem.button?.contentTintColor = .systemRed
            recordItem?.title = "Stop Recording"
        } else {
            setIcon("camera.viewfinder")
            statusItem.button?.contentTintColor = nil
            recordItem?.title = "Record Selection"
        }
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

        let record = NSMenuItem(title: "Record Selection", action: #selector(toggleRecording), keyEquivalent: "d")
        record.keyEquivalentModifierMask = [.shift, .option]
        record.target = self
        recordItem = record
        menu.addItem(record)

        let audio = NSMenuItem(title: "Record System Audio", action: #selector(toggleAudio), keyEquivalent: "")
        audio.target = self
        audio.state = recorder.capturesAudio ? .on : .off
        audioItem = audio
        menu.addItem(audio)

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
        recorder.destination = value
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
            recorder.destination = value
        }
        // Missing key → keep the service's default (audio on).
        if let audio = UserDefaults.standard.object(forKey: audioDefaultsKey) as? Bool {
            recorder.capturesAudio = audio
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
