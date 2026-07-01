import AppKit

/// Selection chrome for recordings, standing in for the `screencapture -i`
/// crosshair that macOS refuses to combine with video capture ("video not
/// valid with -i"): drag a region, or press Space to toggle window mode and
/// click a window to take its frame — the desktop counts as a window, so
/// clicking the wallpaper records the whole screen. Esc cancels.
///
/// The chosen rect is delivered in CG/global top-left coordinates — exactly
/// what `screencapture -v -R` expects. One overlay panel per screen; the
/// panels are non-activating so Snipper stays an accessory app throughout.
final class SelectionOverlay {
    private var panels: [OverlayPanel] = []
    private var completion: ((CGRect?) -> Void)?

    /// Cover every screen and wait for a selection. Calls `completion` once,
    /// on the main queue, with a CG-coordinate rect — or nil on Esc/cancel.
    func begin(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen)
            (panel.contentView as? OverlayView)?.onFinish = { [weak self] rect in
                self?.finish(rect)
            }
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        // Key window status is what routes Space/Esc to the overlay.
        panels.first?.makeKey()
    }

    /// Tear down without a selection (e.g. ⇧⌥D pressed again mid-selection).
    func cancel() { finish(nil) }

    private func finish(_ rect: CGRect?) {
        guard let completion else { return } // already finished
        self.completion = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.arrow.set()
        completion(rect)
    }
}

/// Borderless, non-activating, screen-covering panel that can become key so
/// the overlay view receives Space/Esc without activating the app.
private final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        contentView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    /// Delivers the selection in CG coordinates, or nil for cancel.
    var onFinish: ((CGRect?) -> Void)?

    private enum Mode { case region, window }
    private var mode: Mode = .region

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var hoveredWindowRect: NSRect? // in view coordinates
    private var hoveredWindowCGRect: CGRect?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Subtle dim so the overlay reads as a mode; the selection punches
        // through to full brightness.
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        let selection: NSRect? = {
            switch mode {
            case .region:
                guard let a = dragStart, let b = dragCurrent else { return nil }
                return rect(a, b)
            case .window:
                return hoveredWindowRect
            }
        }()

        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: -0.75, dy: -0.75))
            border.lineWidth = 1.5
            border.stroke()
        }

        drawHint()
    }

    private func drawHint() {
        let text = mode == .region
            ? "Drag to record a region · Space for window · Esc to cancel"
            : "Click a window to record it (desktop = full screen) · Space for region · Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 12
        let box = NSRect(x: bounds.midX - size.width / 2 - pad,
                         y: bounds.maxY - 64,
                         width: size.width + pad * 2, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        text.draw(at: NSPoint(x: box.minX + pad, y: box.minY + 6), withAttributes: attrs)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onFinish?(nil)
        case 49: // Space — toggle region/window mode, like screencapture -i
            mode = (mode == .region) ? .window : .region
            dragStart = nil
            dragCurrent = nil
            if mode == .window { updateHoveredWindow(at: NSEvent.mouseLocation) }
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onFinish?(nil) }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        switch mode {
        case .region:
            dragStart = convert(event.locationInWindow, from: nil)
            dragCurrent = dragStart
        case .window:
            if let cgRect = hoveredWindowCGRect { onFinish?(cgRect) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .region, let a = dragStart, let b = dragCurrent else { return }
        dragStart = nil
        dragCurrent = nil
        let sel = rect(a, b)
        // A stray click isn't a selection; stay in the overlay.
        guard sel.width > 8, sel.height > 8 else { needsDisplay = true; return }
        onFinish?(cgRect(fromViewRect: sel))
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        updateHoveredWindow(at: NSEvent.mouseLocation)
    }

    // MARK: - Window picking

    /// Front-to-back hit test of on-screen windows at `point` (NS global
    /// coords), skipping our own overlay panels and anything above the
    /// normal layer (menu bar, status items) — but keeping the desktop
    /// (negative layer), which makes "click the wallpaper" mean full screen.
    private func updateHoveredWindow(at point: NSPoint) {
        let cgPoint = CGPoint(x: point.x, y: Self.primaryHeight - point.y)
        // windowNumber can fall outside CGWindowID's range (negative for
        // windows without a backing device, and huge sentinel values have
        // been seen in the wild) — a plain conversion traps, so keep only
        // exactly-representable numbers.
        let ourNumbers = Set(NSApp.windows.compactMap { CGWindowID(exactly: $0.windowNumber) })

        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return }

        for entry in info {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer <= 0,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  !ourNumbers.contains(number),
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let cg = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                            width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            guard cg.contains(cgPoint) else { continue }
            hoveredWindowCGRect = cg
            hoveredWindowRect = viewRect(fromCGRect: cg)
            needsDisplay = true
            return
        }
        hoveredWindowCGRect = nil
        hoveredWindowRect = nil
        needsDisplay = true
    }

    // MARK: - Geometry

    private func rect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Height of the primary screen — the anchor for flipping between NS
    /// (bottom-left origin) and CG (top-left origin) global coordinates.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private func cgRect(fromViewRect viewRect: NSRect) -> CGRect {
        guard let window else { return viewRect }
        let nsGlobal = window.convertToScreen(convert(viewRect, to: nil))
        return CGRect(x: nsGlobal.origin.x,
                      y: Self.primaryHeight - nsGlobal.maxY,
                      width: nsGlobal.width, height: nsGlobal.height)
    }

    private func viewRect(fromCGRect cg: CGRect) -> NSRect {
        let nsGlobal = NSRect(x: cg.origin.x,
                              y: Self.primaryHeight - cg.maxY,
                              width: cg.width, height: cg.height)
        guard let window else { return nsGlobal }
        return convert(window.convertFromScreen(nsGlobal), from: nil)
    }
}
