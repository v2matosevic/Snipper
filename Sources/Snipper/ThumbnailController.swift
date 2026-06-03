import AppKit

/// A floating thumbnail in the bottom-right corner, mimicking macOS's own
/// post-screenshot preview: fades in, sits for a few seconds, then fades away.
/// Click it to open the capture; hover to keep it around; ✕ to dismiss.
final class ThumbnailController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private var fileURL: URL?
    private var isTemporary = false

    private let displaySeconds: TimeInterval = 5
    private let shadowMargin: CGFloat = 24
    private let framePadding: CGFloat = 5
    private let screenMargin: CGFloat = 16
    private let maxImage = NSSize(width: 264, height: 172)

    func show(image: NSImage, fileURL: URL, isTemporary: Bool) {
        dismissNow() // replace any preview already on screen

        self.fileURL = fileURL
        self.isTemporary = isTemporary

        let drawn = scaledSize(for: image.size)
        let cardSize = NSSize(width: drawn.width + framePadding * 2,
                              height: drawn.height + framePadding * 2)
        let panelSize = NSSize(width: cardSize.width + shadowMargin * 2,
                               height: cardSize.height + shadowMargin * 2)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        // Container (transparent) → card (rounded, shadowed) → image.
        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.wantsLayer = true

        let card = ThumbnailCardView(frame: NSRect(x: shadowMargin, y: shadowMargin,
                                                   width: cardSize.width, height: cardSize.height))
        card.wantsLayer = true
        if let layer = card.layer {
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer.cornerRadius = 10
            layer.borderWidth = 0.5
            layer.borderColor = NSColor.separatorColor.cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.30
            layer.shadowRadius = 11
            layer.shadowOffset = CGSize(width: 0, height: -3)
            layer.masksToBounds = false
        }

        let imageView = NSImageView(frame: NSRect(x: framePadding, y: framePadding,
                                                  width: drawn.width, height: drawn.height))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        card.addSubview(imageView)

        // ✕ button, top-left, revealed on hover.
        let close = NSButton(frame: NSRect(x: -7, y: cardSize.height - 13, width: 20, height: 20))
        close.bezelStyle = .inline
        close.isBordered = false
        close.title = ""
        close.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Dismiss")
        close.imagePosition = .imageOnly
        close.contentTintColor = .secondaryLabelColor
        close.target = self
        close.action = #selector(closeTapped)
        close.isHidden = true
        card.addSubview(close)

        card.onClick = { [weak self] in self?.openTapped() }
        card.onHover = { [weak self] inside in
            close.isHidden = !inside
            if inside { self?.cancelDismissTimer() }
            else { self?.scheduleDismiss(after: 1.5) }
        }

        container.addSubview(card)
        panel.contentView = container

        // Bottom-right of the screen under the cursor (fallback: main screen),
        // sitting above the Dock via visibleFrame.
        let screen = screenUnderCursor()
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.maxX - panelSize.width + shadowMargin - screenMargin,
                             y: vf.minY - shadowMargin + screenMargin)

        // Fade in at the final position. (Animating a borderless panel's frame
        // origin via animator() proved unreliable — alpha animates dependably.)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        scheduleDismiss(after: displaySeconds)
    }

    // MARK: - Actions

    @objc private func openTapped() {
        if let url = fileURL {
            isTemporary = false // opened → let it live; don't delete underneath the viewer
            NSWorkspace.shared.open(url)
        }
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Dismiss / timers

    private func scheduleDismiss(after seconds: TimeInterval) {
        cancelDismissTimer()
        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelDismissTimer() {
        dismissWork?.cancel()
        dismissWork = nil
    }

    private func dismiss(animated: Bool) {
        cancelDismissTimer()
        guard let panel else { return }
        guard animated else { dismissNow(); return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.dismissNow()
        })
    }

    private func dismissNow() {
        cancelDismissTimer()
        panel?.orderOut(nil)
        panel = nil
        if isTemporary, let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
        isTemporary = false
    }

    // MARK: - Geometry

    private func scaledSize(for size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return maxImage }
        let scale = min(maxImage.width / size.width, maxImage.height / size.height, 1)
        return NSSize(width: max(1, (size.width * scale).rounded()),
                      height: max(1, (size.height * scale).rounded()))
    }

    private func screenUnderCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

/// Card view that reports clicks and hover so the controller can open the file
/// or pause auto-dismiss.
private final class ThumbnailCardView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
