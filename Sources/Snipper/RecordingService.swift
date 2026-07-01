import AppKit
import AVFoundation

/// Drives screen recording through the native `screencapture -v` tool and
/// routes the finished movie to the save folder (and its file URL to the
/// clipboard). Same philosophy as `ScreenshotService` — shell out, don't
/// reimplement — with one wrinkle: macOS refuses `-v` with `-i` ("video not
/// valid with -i"), so the selection UI is our own `SelectionOverlay` (drag a
/// region, Space for window mode, Esc cancels) and the chosen rect is handed
/// to `screencapture -v -R`. No extra permissions beyond the Screen Recording
/// grant the screenshots already use.
final class RecordingService {
    /// What a finished recording yields: a poster frame (first frame with a
    /// play badge, for the corner preview) and the saved movie.
    struct Result {
        let poster: NSImage
        let url: URL
    }

    /// Mirrors the screenshot destination choice, with one difference: a movie
    /// can't live on the pasteboard as raw bits the way an image can, so
    /// "clipboard" for a recording means "put the file's URL on the
    /// pasteboard" — and that URL has to keep pointing at a real file. So
    /// recordings are always saved to the folder, even on "Clipboard only".
    var destination: ScreenshotService.Destination = .both

    /// Called on the main queue after a recording is saved.
    var onCapture: ((Result) -> Void)?

    /// Fired on the main queue whenever recording starts or stops, so the
    /// menu bar can flip its icon and menu title.
    var onStateChange: ((Bool) -> Void)?

    /// Capture system audio (`-A`) along with the video — what makes a
    /// recorded browser video worth keeping. First use may trigger macOS's
    /// one-time system-audio-recording consent prompt.
    var capturesAudio = true

    private enum Phase { case idle, selecting, recording }
    private var phase: Phase = .idle
    private var overlay: SelectionOverlay?
    private var task: Process?
    private var recordingURL: URL? // temp file of the recording in flight
    private let saveDirectory: URL

    init(saveDirectory: URL) {
        self.saveDirectory = saveDirectory
    }

    /// One hotkey, three meanings: open the selector, abandon the selector,
    /// or stop the recording in flight.
    func toggle() {
        switch phase {
        case .idle:
            beginSelection()
        case .selecting:
            overlay?.cancel() // completion(nil) resets phase
        case .recording:
            // SIGINT is screencapture's "stop recording" signal: it finalizes
            // the movie and exits, which fires the termination handler.
            task?.interrupt()
        }
    }

    private func beginSelection() {
        phase = .selecting
        let overlay = SelectionOverlay()
        self.overlay = overlay
        overlay.begin { [weak self] cgRect in
            guard let self else { return }
            self.overlay = nil
            guard let cgRect else { self.phase = .idle; return }
            // Give the compositor a beat to remove the overlay chrome so it
            // can't leak into the first frames of the recording.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.startRecording(rect: cgRect.integral)
            }
        }
    }

    private func startRecording(rect: CGRect) {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("record-\(UUID().uuidString).mov")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -v : record video
        // -R : the rect chosen in the selection overlay (CG global coords)
        // -k : show mouse clicks — recordings are mostly demos and bug repros,
        //      where "what did I click" is the whole point
        // -A : system audio, when enabled in the menu
        var arguments = ["-v", "-k"]
        if capturesAudio { arguments.append("-A") }
        arguments += ["-R", "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))",
                      tempURL.path]
        task.arguments = arguments

        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.finished(tempURL: tempURL) }
        }

        do {
            try task.run()
        } catch {
            NSLog("Snipper: failed to launch screencapture -v: \(error)")
            phase = .idle
            return
        }
        self.task = task
        recordingURL = tempURL
        phase = .recording
        onStateChange?(true)
    }

    /// App is quitting: stop a recording in flight, wait for screencapture to
    /// finalize the movie, and move it into the save folder synchronously —
    /// the normal async result pipeline won't get to run again. Without this
    /// the child process outlives Snipper and records until the machine
    /// sleeps, and the footage is stranded in /tmp.
    func shutdown() {
        guard let task, task.isRunning else { return }
        task.interrupt()
        task.waitUntilExit() // brief — SIGINT finalize takes well under a second
        if let url = recordingURL { _ = persist(url) }
    }

    // MARK: - Result handling

    private func finished(tempURL: URL) {
        task = nil
        recordingURL = nil
        phase = .idle
        onStateChange?(false)

        // No file (or an empty one) → the recorder died before producing
        // anything worth keeping.
        let attributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
        guard (attributes?[.size] as? Int ?? 0) > 0 else { return }

        guard let saved = persist(tempURL) else {
            NSLog("Snipper: couldn't move the recording into the save folder")
            return
        }
        if destination != .folderOnly {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([saved as NSURL])
        }

        posterFrame(for: saved) { [weak self] poster in
            self?.onCapture?(Result(poster: poster, url: saved))
        }
    }

    private func persist(_ tempURL: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: saveDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let destURL = saveDirectory.appendingPathComponent("Recording \(formatter.string(from: Date())).mov")

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

    // MARK: - Poster frame

    /// Grab the first frame and stamp a play badge on it so the corner preview
    /// reads as a video, not a screenshot. Completion runs on the main queue.
    private func posterFrame(for url: URL, completion: @escaping (NSImage) -> Void) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
            DispatchQueue.main.async {
                guard let cgImage else {
                    // Fallback: a plain film glyph, so the preview still shows up.
                    let fallback = NSImage(systemSymbolName: "film", accessibilityDescription: "Recording")
                        ?? NSImage(size: NSSize(width: 264, height: 172))
                    completion(fallback)
                    return
                }
                let poster = NSImage(cgImage: cgImage,
                                     size: NSSize(width: cgImage.width, height: cgImage.height))
                completion(Self.withPlayBadge(poster))
            }
        }
    }

    private static func withPlayBadge(_ poster: NSImage) -> NSImage {
        let size = poster.size
        guard size.width > 0, size.height > 0 else { return poster }
        return NSImage(size: size, flipped: false) { rect in
            poster.draw(in: rect)

            // Dark disc + white triangle, drawn by hand so it stays legible on
            // any footage (an SF Symbol would draw template-black).
            let side = min(rect.width, rect.height) * 0.30
            let disc = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                              width: side, height: side)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: disc).fill()

            let r = side * 0.30
            let triangle = NSBezierPath()
            triangle.move(to: CGPoint(x: rect.midX - r * 0.55, y: rect.midY - r))
            triangle.line(to: CGPoint(x: rect.midX - r * 0.55, y: rect.midY + r))
            triangle.line(to: CGPoint(x: rect.midX + r * 1.05, y: rect.midY))
            triangle.close()
            NSColor.white.setFill()
            triangle.fill()
            return true
        }
    }
}
