import AppKit
import CoreImage
import Vision

/// A lightweight markup editor for a freshly-captured snip. Opened from the
/// pencil button on the corner thumbnail. Lets you draw rectangles, ellipses,
/// freehand strokes and arrows over the image, then copies the annotated result
/// to the clipboard (and overwrites the saved PNG when the snip lives in a file).
///
/// Annotations are kept as a list of vector shapes drawn on top of the base
/// image — never painted into the pixels — so undo is trivial and every stroke
/// stays crisp. The flattened export is rendered at the image's true pixel
/// resolution so an annotated Retina snip is exactly as sharp as the original.
final class AnnotationEditorWindowController: NSObject, NSWindowDelegate {
    enum Tool: Int { case rectangle = 0, ellipse, freehand, arrow, blur, step }

    /// One drawn shape. For rectangle/ellipse/arrow/blur `points` is
    /// [start, end]; for freehand it's every sampled point along the drag; for
    /// step it's the single badge position. Step badges carry no number — it's
    /// derived from draw order, so undo renumbers the rest automatically.
    struct Annotation {
        var tool: Tool
        var points: [CGPoint]
        var color: NSColor
        var lineWidth: CGFloat
    }

    /// Called once the editor window has closed, so the owner can drop its
    /// reference and let the controller deallocate.
    var onClose: (() -> Void)?

    private let baseImage: NSImage
    private let pixelSize: NSSize
    private let fileURL: URL
    private let isTemporary: Bool

    private var window: NSWindow!
    private var canvas: AnnotationCanvasView!

    private let toolbarHeight: CGFloat = 48

    /// - Parameters:
    ///   - url: the snip on disk (a saved PNG, or a throwaway temp for
    ///     clipboard-only captures). The image is loaded fresh from here so the
    ///     export can match its real pixel dimensions.
    ///   - isTemporary: true when `url` is a temp file the editor now owns and
    ///     must delete on close.
    init?(url: URL, isTemporary: Bool) {
        guard let image = NSImage(contentsOf: url) else { return nil }
        self.baseImage = image
        self.fileURL = url
        self.isTemporary = isTemporary
        self.pixelSize = Self.pixelSize(of: image)
        super.init()
        buildWindow()
    }

    // MARK: - Presentation

    /// Show the editor and take focus. Snipper normally runs as a menu-bar agent
    /// (`.accessory`) and can't become key; the owner flips the app to `.regular`
    /// while any editor is open (and back once the last one closes) so the
    /// controls and ⌘-keys work — see `AppDelegate.openEditor`.
    func present() {
        window.makeKeyAndOrderFront(nil)
        window.center()
        window.makeFirstResponder(canvas)
    }

    func windowWillClose(_ notification: Notification) {
        if isTemporary { try? FileManager.default.removeItem(at: fileURL) }
        onClose?()
    }

    // MARK: - Window / UI construction

    private func buildWindow() {
        let display = displaySize()
        let contentSize = NSSize(width: display.width,
                                 height: display.height + toolbarHeight)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Snip"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
        content.wantsLayer = true

        // Canvas fills everything below the toolbar.
        canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0,
                                                    width: display.width, height: display.height))
        canvas.autoresizingMask = [.width, .height]
        canvas.configure(image: baseImage, color: .systemRed, lineWidth: 4, tool: .rectangle)
        canvas.onCancel = { [weak self] in self?.window.performClose(nil) }
        content.addSubview(canvas)

        content.addSubview(buildToolbar(width: display.width))
        window.contentView = content
    }

    private func buildToolbar(width: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: displaySize().height,
                                       width: width, height: toolbarHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Tool picker (radio-style): rectangle · ellipse · freehand · arrow.
        let tools = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: self,
                                       action: #selector(toolChanged(_:)))
        tools.segmentCount = 6
        let symbols = ["rectangle", "circle", "scribble", "arrow.up.right",
                       "circle.grid.3x3.fill", "1.circle"]
        let names = ["Rectangle", "Ellipse", "Freehand", "Arrow", "Blur", "Step"]
        for (i, sym) in symbols.enumerated() {
            tools.setImage(NSImage(systemSymbolName: sym, accessibilityDescription: names[i]), forSegment: i)
            tools.setWidth(40, forSegment: i)
        }
        tools.selectedSegment = 0
        tools.sizeToFit()

        let colorWell = NSColorWell()
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))

        let widthSlider = NSSlider(value: 4, minValue: 1, maxValue: 24, target: self,
                                   action: #selector(widthChanged(_:)))
        widthSlider.isContinuous = true

        let undo = toolButton("arrow.uturn.backward", "Undo", #selector(undoTapped))
        undo.keyEquivalent = "z"
        undo.keyEquivalentModifierMask = .command

        // OCR: extract the snip's text (error dialogs, logs) to the clipboard —
        // pasting text into an AI prompt beats pasting pixels.
        let ocr = toolButton("text.viewfinder", "Copy Text (OCR)", #selector(ocrTapped))
        ocr.toolTip = "Copy text (OCR)"

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        copy.bezelStyle = .rounded
        copy.keyEquivalent = "\r" // default button — Return copies
        copy.sizeToFit()

        let stack = NSStackView(views: [tools, colorWell, widthSlider, undo, ocr])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        // "Save" and "Copy Path" only make sense when the snip is backed by a
        // real file (a temp's path dies with the editor).
        if !isTemporary {
            let path = toolButton("folder", "Copy Path", #selector(copyPathTapped))
            path.toolTip = "Copy file path"
            stack.addArrangedSubview(path)

            let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
            save.bezelStyle = .rounded
            save.sizeToFit()
            stack.addArrangedSubview(save)
        }
        stack.addArrangedSubview(copy)

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            colorWell.widthAnchor.constraint(equalToConstant: 38),
            colorWell.heightAnchor.constraint(equalToConstant: 24),
            widthSlider.widthAnchor.constraint(equalToConstant: 90),
        ])
        return bar
    }

    private func toolButton(_ symbol: String, _ desc: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: desc)!,
                         target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.sizeToFit()
        return b
    }

    // MARK: - Toolbar actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        canvas.tool = Tool(rawValue: sender.selectedSegment) ?? .rectangle
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvas.strokeColor = sender.color
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        canvas.lineWidth = CGFloat(sender.doubleValue)
    }

    @objc private func undoTapped() { canvas.undo() }

    @objc private func copyPathTapped() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fileURL.path, forType: .string)
        flashTitle("Path copied")
    }

    /// Recognize the snip's text off the main thread and put it on the
    /// clipboard. The window stays open — OCR is usually a side-grab on the way
    /// to annotating.
    @objc private func ocrTapped() {
        guard let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSSound.beep(); return
        }
        flashTitle("Reading text…", revertAfter: 0)
        let request = VNRecognizeTextRequest { [weak self] request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                guard let self else { return }
                guard !lines.isEmpty else {
                    self.flashTitle("No text found")
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(lines.joined(separator: "\n"), forType: .string)
                self.flashTitle("Text copied")
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cg)
            do { try handler.perform([request]) } catch {
                DispatchQueue.main.async { [weak self] in self?.flashTitle("OCR failed") }
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
            self.window.title = "Edit Snip"
        }
    }

    @objc private func copyTapped() {
        guard let image = flattened() else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        window.performClose(nil)
    }

    @objc private func saveTapped() {
        guard let rep = renderRep(),
              let png = rep.representation(using: .png, properties: [:]) else {
            NSSound.beep(); return
        }
        do {
            try png.write(to: fileURL)
        } catch {
            NSLog("Snipper: failed to save annotated snip: \(error)")
            NSSound.beep(); return
        }
        // Keep the app's clipboard-first habit: a saved annotation is also copied.
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        window.performClose(nil)
    }

    // MARK: - Flatten / export

    /// Render base image + annotations into a bitmap at full pixel resolution.
    private func renderRep() -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        // 1 point == 1 pixel so the exported PNG carries no surprise DPI scaling.
        rep.size = pixelSize

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        let fullRect = NSRect(origin: .zero, size: pixelSize)
        baseImage.draw(in: fullRect)

        // Shapes are stored in canvas-point space; scale them up to pixels.
        let scale = pixelSize.width / canvas.bounds.width
        canvas.drawAnnotations(canvas.annotations, scale: scale)

        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func flattened() -> NSImage? {
        guard let rep = renderRep() else { return nil }
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Geometry

    /// Fit the image into ~90% of the active screen; cap upscaling of small
    /// snips at 2× so a tiny UI grab is still comfortable to draw on.
    private func displaySize() -> NSSize {
        let visible = (NSScreen.main?.visibleFrame.size) ?? NSSize(width: 1440, height: 900)
        let maxW = visible.width * 0.9
        let maxH = visible.height * 0.9 - toolbarHeight
        let scale = min(maxW / pixelSize.width, maxH / pixelSize.height, 2)
        return NSSize(width: max(1, (pixelSize.width * scale).rounded()),
                      height: max(1, (pixelSize.height * scale).rounded()))
    }

    /// True pixel dimensions of the snip — read from the bitmap rep, since
    /// `NSImage.size` is in DPI-dependent points and would lie for Retina grabs.
    private static func pixelSize(of image: NSImage) -> NSSize {
        let reps = image.representations
        if let best = reps.max(by: { $0.pixelsWide < $1.pixelsWide }), best.pixelsWide > 0 {
            return NSSize(width: best.pixelsWide, height: best.pixelsHigh)
        }
        return image.size
    }
}

/// The drawing surface: paints the base image plus the live annotation list and
/// turns mouse drags into shapes. Coordinates are kept in the view's own point
/// space; the controller scales them to pixels at export time.
final class AnnotationCanvasView: NSView {
    typealias Tool = AnnotationEditorWindowController.Tool
    typealias Annotation = AnnotationEditorWindowController.Annotation

    private(set) var annotations: [Annotation] = []
    private var current: Annotation?

    var tool: Tool = .rectangle
    var strokeColor: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var onCancel: (() -> Void)?

    private var image: NSImage?

    // Pixelated copy of the base image, built once on first use of the blur
    // tool. Blur regions just draw the matching crop of this image, so the
    // effect is identical on screen and in the export.
    private var pixelatedImage: NSImage?
    private var pixelatedSize: NSSize = .zero

    func configure(image: NSImage, color: NSColor, lineWidth: CGFloat, tool: Tool) {
        self.image = image
        self.strokeColor = color
        self.lineWidth = lineWidth
        self.tool = tool
        needsDisplay = true
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
        var live = annotations
        if let current { live.append(current) }
        drawAnnotations(live, scale: 1)
    }

    /// Stroke every annotation. `scale` maps stored point coords to the target
    /// space (1 on screen, pixels/points on export).
    func drawAnnotations(_ list: [Annotation], scale: CGFloat) {
        var stepNumber = 0
        for ann in list {
            switch ann.tool {
            case .blur:
                drawBlur(ann, scale: scale)
            case .step:
                stepNumber += 1
                drawStep(ann, number: stepNumber, scale: scale)
            default:
                ann.color.setStroke()
                let path = bezierPath(for: ann, scale: scale)
                path.lineWidth = max(0.5, ann.lineWidth * scale)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
    }

    /// Paint the matching crop of the pixelated image over the dragged rect.
    private func drawBlur(_ ann: Annotation, scale: CGFloat) {
        guard ann.points.count >= 2, let pixelated = pixelatedOrBuild() else { return }
        let a = CGPoint(x: ann.points[0].x * scale, y: ann.points[0].y * scale)
        let b = CGPoint(x: ann.points[1].x * scale, y: ann.points[1].y * scale)
        let dest = rect(a, b)
        // Map the annotation rect (canvas points) into the pixelated image's
        // own coordinate space (1 point == 1 source pixel).
        let toSource = pixelatedSize.width / bounds.width
        let src = NSRect(x: min(ann.points[0].x, ann.points[1].x) * toSource,
                         y: min(ann.points[0].y, ann.points[1].y) * toSource,
                         width: abs(ann.points[0].x - ann.points[1].x) * toSource,
                         height: abs(ann.points[0].y - ann.points[1].y) * toSource)
        pixelated.draw(in: dest, from: src, operation: .sourceOver, fraction: 1,
                       respectFlipped: false,
                       hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }

    /// A filled circle badge with the step's number centered in white.
    private func drawStep(_ ann: Annotation, number: Int, scale: CGFloat) {
        guard let p = ann.points.first else { return }
        let center = CGPoint(x: p.x * scale, y: p.y * scale)
        let radius = max(14, ann.lineWidth * 3.5) * scale
        let circleRect = NSRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)
        let circle = NSBezierPath(ovalIn: circleRect)
        ann.color.setFill()
        circle.fill()
        NSColor.white.setStroke()
        circle.lineWidth = max(1, 2 * scale)
        circle.stroke()

        let text = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: radius * 1.05),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: center.x - size.width / 2,
                              y: center.y - size.height / 2),
                  withAttributes: attrs)
    }

    /// Build the pixelated copy lazily — most edits never touch the blur tool.
    private func pixelatedOrBuild() -> NSImage? {
        if let pixelatedImage { return pixelatedImage }
        guard let image,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let filter = CIFilter(name: "CIPixellate") else { return nil }
        let input = CIImage(cgImage: cg)
        filter.setValue(input, forKey: kCIInputImageKey)
        // Block size tracks image width so the mosaic reads the same on a tiny
        // UI grab and a full-screen Retina capture.
        filter.setValue(max(8, CGFloat(cg.width) / 80), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage,
              let outCG = CIContext().createCGImage(output, from: input.extent) else { return nil }
        pixelatedSize = NSSize(width: cg.width, height: cg.height)
        let result = NSImage(cgImage: outCG, size: pixelatedSize)
        pixelatedImage = result
        return result
    }

    private func bezierPath(for ann: Annotation, scale: CGFloat) -> NSBezierPath {
        let pts = ann.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        let path = NSBezierPath()
        switch ann.tool {
        case .rectangle:
            guard pts.count >= 2 else { break }
            path.appendRect(rect(pts[0], pts[1]))
        case .ellipse:
            guard pts.count >= 2 else { break }
            path.appendOval(in: rect(pts[0], pts[1]))
        case .freehand:
            guard let first = pts.first else { break }
            path.move(to: first)
            for p in pts.dropFirst() { path.line(to: p) }
        case .arrow:
            guard pts.count >= 2 else { break }
            appendArrow(to: path, from: pts[0], to: pts[1], lineWidth: ann.lineWidth * scale)
        case .blur, .step:
            break // drawn directly in drawAnnotations, never stroked as a path
        }
        return path
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func appendArrow(to path: NSBezierPath, from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) {
        path.move(to: start)
        path.line(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, lineWidth * 3.5)
        let headAngle = CGFloat.pi / 6 // 30°
        let left = CGPoint(x: end.x - headLength * cos(angle - headAngle),
                           y: end.y - headLength * sin(angle - headAngle))
        let right = CGPoint(x: end.x - headLength * cos(angle + headAngle),
                            y: end.y - headLength * sin(angle + headAngle))
        path.move(to: end); path.line(to: left)
        path.move(to: end); path.line(to: right)
    }

    // MARK: - Mouse → shapes

    override func mouseDown(with event: NSEvent) {
        let p = clamp(convert(event.locationInWindow, from: nil))
        current = Annotation(tool: tool, points: [p, p], color: strokeColor, lineWidth: lineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard current != nil else { return }
        let p = clamp(convert(event.locationInWindow, from: nil))
        switch current!.tool {
        case .freehand:
            current!.points.append(p)
        case .step:
            current!.points[0] = p // dragging fine-positions the badge
        default:
            current!.points[1] = p
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let shape = current else { return }
        current = nil
        if isMeaningful(shape) { annotations.append(shape) }
        needsDisplay = true
    }

    /// Drop accidental dot-clicks: a shape that never really moved.
    private func isMeaningful(_ ann: Annotation) -> Bool {
        if ann.tool == .step { return true } // a step IS a click
        if ann.tool == .freehand { return ann.points.count > 1 }
        guard ann.points.count >= 2 else { return false }
        return hypot(ann.points[0].x - ann.points[1].x, ann.points[0].y - ann.points[1].y) > 3
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    // MARK: - Editing

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
