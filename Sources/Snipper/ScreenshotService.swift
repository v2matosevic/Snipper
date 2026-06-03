import AppKit

/// Drives macOS's native interactive capture (`/usr/sbin/screencapture -i`) and
/// routes the result to the clipboard and/or a save folder.
///
/// Shelling out to the system tool gives us the exact crosshair selection UI of
/// ⌘⇧4 (drag a region, or press Space to grab a window) for free — no custom
/// overlay, no ScreenCaptureKit plumbing.
final class ScreenshotService {
    enum Destination: Int {
        case both = 0          // copy to clipboard AND save a PNG (default)
        case clipboardOnly = 1
        case folderOnly = 2
    }

    /// What a finished capture yields: the image (for the corner preview), the
    /// file to open when the preview is clicked, and whether that file is a
    /// throwaway temp that should be deleted once the preview goes away.
    struct Result {
        let image: NSImage
        let url: URL
        let isTemporary: Bool
    }

    var destination: Destination = .both

    /// Called on the main queue after a successful capture.
    var onCapture: ((Result) -> Void)?

    /// `~/Pictures/Snipper` — where snips land when the destination includes a folder.
    var saveDirectory: URL {
        let pictures = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("Snipper", isDirectory: true)
    }

    /// Launches the native region selector. Returns immediately; the result is
    /// handled asynchronously once the user finishes (or cancels) the selection.
    func captureInteractive() {
        // Always capture to a temp file first so we can reliably do BOTH
        // clipboard and folder (and show a preview) from one shot.
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snip-\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i : interactive selection (drag a region, Space toggles window mode)
        // -o : omit the window shadow when capturing a window
        // -x : silent — no camera shutter sound
        task.arguments = ["-i", "-o", "-x", tempURL.path]

        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleResult(tempURL: tempURL) }
        }

        do {
            try task.run()
        } catch {
            NSLog("Snipper: failed to launch screencapture: \(error)")
        }
    }

    // MARK: - Result handling

    private func handleResult(tempURL: URL) {
        let fm = FileManager.default
        // No file written → the user pressed Esc / cancelled. Nothing to do.
        guard fm.fileExists(atPath: tempURL.path),
              let image = NSImage(contentsOf: tempURL) else { return }

        if destination != .folderOnly {
            copyToClipboard(image)
        }

        let result: Result
        switch destination {
        case .both, .folderOnly:
            let saved = persist(tempURL) ?? tempURL
            result = Result(image: image, url: saved, isTemporary: saved == tempURL)
        case .clipboardOnly:
            // Keep the temp file so the corner preview can open it; it's cleaned
            // up when the preview is dismissed.
            result = Result(image: image, url: tempURL, isTemporary: true)
        }

        onCapture?(result)
    }

    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @discardableResult
    private func persist(_ tempURL: URL) -> URL? {
        let fm = FileManager.default
        let dir = saveDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let destURL = dir.appendingPathComponent("Snip \(formatter.string(from: Date())).png")

        do {
            try fm.moveItem(at: tempURL, to: destURL)
            return destURL
        } catch {
            // Fall back to copy (e.g. cross-volume move failure).
            try? fm.copyItem(at: tempURL, to: destURL)
            try? fm.removeItem(at: tempURL)
            return fm.fileExists(atPath: destURL.path) ? destURL : nil
        }
    }
}
