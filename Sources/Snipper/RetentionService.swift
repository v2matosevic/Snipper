import Foundation

/// Keeps `~/Pictures/Snipper` a scratchpad, not an archive: captures older
/// than the retention window are deleted automatically. Sweeps at launch and
/// twice a day thereafter (the app is a long-running agent, so launch alone
/// isn't enough).
///
/// Only files matching Snipper's own naming (`Snip *.png` / `Recording *.mov`)
/// are touched — anything the user parked in the folder by hand is left alone.
final class RetentionService {
    /// Days to keep captures. Override without a rebuild:
    /// `defaults write com.version2.snipper retentionDays -int 90`
    /// (a value ≤ 0 disables the sweep entirely).
    private static let defaultDays = 30
    private static let defaultsKey = "retentionDays"

    private let directory: URL
    private let days: Int
    private var timer: Timer?

    init(directory: URL) {
        self.directory = directory
        if let override = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Int {
            self.days = override
        } else {
            self.days = Self.defaultDays
        }
    }

    func start() {
        guard days > 0 else { return }
        sweep()
        let timer = Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in
            self?.sweep()
        }
        timer.tolerance = 3600 // housekeeping — whenever is fine
        self.timer = timer
    }

    private func sweep() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: [.creationDateKey],
                                                      options: .skipsHiddenFiles) else { return }
        for url in files {
            let name = url.lastPathComponent
            let isOurs = (name.hasPrefix("Snip ") && url.pathExtension == "png")
                      || (name.hasPrefix("Recording ") && url.pathExtension == "mov")
            guard isOurs,
                  let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                  created < cutoff else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
