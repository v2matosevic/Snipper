import AppKit
import AVFoundation
import AVKit

/// A minimal post-recording editor, the video counterpart to the markup
/// editor: plays the movie and exposes QuickTime's native trim UI
/// (`AVPlayerView.beginTrimming` — the yellow handles). Confirming a trim
/// re-exports the selected range losslessly (passthrough, no re-encode) and
/// overwrites the file in place, so the saved recording is exactly what you
/// kept.
final class TrimEditorWindowController: NSObject, NSWindowDelegate {
    /// Called once the editor window has closed, so the owner can drop its
    /// reference and let the controller deallocate.
    var onClose: (() -> Void)?

    private let fileURL: URL
    private var window: NSWindow!
    private var playerView: AVPlayerView!

    private let toolbarHeight: CGFloat = 48

    init(url: URL) {
        self.fileURL = url
        super.init()
        buildWindow()
    }

    // MARK: - Presentation

    /// Show the editor and take focus. Same activation-policy dance as the
    /// markup editor — see `AppDelegate.openEditor`.
    func present() {
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        onClose?()
    }

    // MARK: - Window / UI construction

    private func buildWindow() {
        // Recordings are arbitrary aspect ratios; the player letterboxes, so a
        // comfortable fixed fraction of the screen is enough.
        let visible = (NSScreen.main?.visibleFrame.size) ?? NSSize(width: 1440, height: 900)
        let display = NSSize(width: (visible.width * 0.62).rounded(),
                             height: (visible.height * 0.62).rounded())
        let contentSize = NSSize(width: display.width,
                                 height: display.height + toolbarHeight)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Recording"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
        content.wantsLayer = true

        playerView = AVPlayerView(frame: NSRect(x: 0, y: 0,
                                                width: display.width, height: display.height))
        playerView.autoresizingMask = [.width, .height]
        playerView.controlsStyle = .inline // trimming requires the inline scrubber
        playerView.player = AVPlayer(url: fileURL)
        content.addSubview(playerView)

        content.addSubview(buildToolbar(width: display.width, y: display.height))
        window.contentView = content
    }

    private func buildToolbar(width: CGFloat, y: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: y, width: width, height: toolbarHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let path = NSButton(image: NSImage(systemSymbolName: "folder",
                                           accessibilityDescription: "Copy Path")!,
                            target: self, action: #selector(copyPathTapped))
        path.bezelStyle = .texturedRounded
        path.toolTip = "Copy file path"
        path.sizeToFit()

        let copy = NSButton(title: "Copy File", target: self, action: #selector(copyFileTapped))
        copy.bezelStyle = .rounded
        copy.toolTip = "Put the movie file on the clipboard"
        copy.sizeToFit()

        let trim = NSButton(title: "Trim", target: self, action: #selector(trimTapped))
        trim.bezelStyle = .rounded
        trim.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Trim")
        trim.imagePosition = .imageLeading
        trim.keyEquivalent = "\r" // default button — trimming is why you're here
        trim.sizeToFit()

        let stack = NSStackView(views: [path, copy, trim])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    // MARK: - Toolbar actions

    @objc private func copyPathTapped() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fileURL.path, forType: .string)
        flashTitle("Path copied")
    }

    @objc private func copyFileTapped() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
        flashTitle("File copied")
    }

    @objc private func trimTapped() {
        guard playerView.canBeginTrimming else { NSSound.beep(); return }
        playerView.beginTrimming { [weak self] result in
            DispatchQueue.main.async {
                guard let self, result == .okButton else { return }
                self.exportTrim()
            }
        }
    }

    // MARK: - Export

    /// The trim UI records its selection on the player item as
    /// `reversePlaybackEndTime` (in-point) / `forwardPlaybackEndTime`
    /// (out-point); export that range over the original file.
    private func exportTrim() {
        guard let item = playerView.player?.currentItem else { return }
        let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
        guard end > start else { NSSound.beep(); return }

        guard let export = AVAssetExportSession(asset: item.asset,
                                                presetName: AVAssetExportPresetPassthrough) else {
            NSSound.beep(); return
        }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trim-\(UUID().uuidString).mov")
        export.outputURL = tempURL
        export.outputFileType = .mov
        export.timeRange = CMTimeRange(start: start, end: end)

        flashTitle("Trimming…", revertAfter: 0)
        export.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard export.status == .completed else {
                    NSLog("Snipper: trim export failed: \(String(describing: export.error))")
                    self.flashTitle("Trim failed")
                    return
                }
                do {
                    _ = try FileManager.default.replaceItemAt(self.fileURL, withItemAt: tempURL)
                } catch {
                    NSLog("Snipper: couldn't overwrite the recording: \(error)")
                    self.flashTitle("Trim failed")
                    return
                }
                // Reload so what's on screen is the file now on disk.
                self.playerView.player = AVPlayer(url: self.fileURL)
                self.flashTitle("Trimmed & saved")
            }
        }
    }

    /// Briefly swap the window title as lightweight feedback, then restore it.
    /// `revertAfter: 0` leaves the message up until the next flash.
    private func flashTitle(_ message: String, revertAfter seconds: TimeInterval = 1.6) {
        window.title = message
        guard seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.window.title == message else { return }
            self.window.title = "Edit Recording"
        }
    }
}
