import Foundation
import Combine

class AppState: ObservableObject {
    // Deferred navigation from Home screen shortcuts
    @Published var pendingNavigation: NavItem?

    // Settings (persisted)
    @Published var outputFolder: URL {
        didSet { UserDefaults.standard.set(outputFolder.path, forKey: "outputFolder") }
    }
    @Published var filenamePrefix: String {
        didSet { UserDefaults.standard.set(filenamePrefix, forKey: "filenamePrefix") }
    }
    @Published var defaultCaptureMode: CaptureMode {
        didSet { UserDefaults.standard.set(defaultCaptureMode.rawValue, forKey: "captureMode") }
    }
    @Published var autoGenerateProxy: Bool {
        didSet { UserDefaults.standard.set(autoGenerateProxy, forKey: "autoGenerateProxy") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    // Recent captures (last 5)
    @Published var recentCaptures: [RecentCapture] = []

    // Disk space on output volume
    @Published var availableDiskSpaceGB: Double = 0

    init() {
        let defaults = UserDefaults.standard
        let defaultMovies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())

        if let path = defaults.string(forKey: "outputFolder") {
            outputFolder = URL(fileURLWithPath: path)
        } else {
            outputFolder = defaultMovies
        }
        filenamePrefix = defaults.string(forKey: "filenamePrefix") ?? "tape"
        defaultCaptureMode = CaptureMode(rawValue: defaults.string(forKey: "captureMode") ?? "") ?? .dvrescuePipe
        autoGenerateProxy = defaults.object(forKey: "autoGenerateProxy") as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true

        loadRecentCaptures()
        refreshDiskSpace()
    }

    func refreshDiskSpace() {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: outputFolder.path),
              let free = attrs[.systemFreeSize] as? Int64 else { return }
        availableDiskSpaceGB = Double(free) / 1_000_000_000
    }

    func nextOutputURL(date: Date = Date()) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: date)
        var counter = 1
        while true {
            let name = String(format: "%@_%@_%03d.dv", filenamePrefix, dateStr, counter)
            let url = outputFolder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }

    func addRecentCapture(url: URL, tapeLabel: String) {
        let capture = RecentCapture(url: url, tapeLabel: tapeLabel, date: Date())
        recentCaptures.insert(capture, at: 0)
        if recentCaptures.count > 5 { recentCaptures = Array(recentCaptures.prefix(5)) }
        saveRecentCaptures()
    }

    private func saveRecentCaptures() {
        let data = recentCaptures.compactMap { c -> [String: String]? in
            ["url": c.url.path, "label": c.tapeLabel, "date": ISO8601DateFormatter().string(from: c.date)]
        }
        UserDefaults.standard.set(data, forKey: "recentCaptures")
    }

    private func loadRecentCaptures() {
        guard let data = UserDefaults.standard.array(forKey: "recentCaptures") as? [[String: String]] else { return }
        recentCaptures = data.compactMap { dict in
            guard let path = dict["url"], let label = dict["label"], let dateStr = dict["date"],
                  let date = ISO8601DateFormatter().date(from: dateStr) else { return nil }
            return RecentCapture(url: URL(fileURLWithPath: path), tapeLabel: label, date: date)
        }
    }
}

struct RecentCapture: Identifiable {
    let id = UUID()
    let url: URL
    let tapeLabel: String
    let date: Date

    var displayName: String { tapeLabel.isEmpty ? url.lastPathComponent : tapeLabel }
}

enum CaptureMode: String, CaseIterable {
    case dvrescuePipe = "dvrescue_pipe"
    case ffmpegOnly   = "ffmpeg_only"

    var displayName: String {
        switch self {
        case .dvrescuePipe: return "dvrescue pipe (recommended)"
        case .ffmpegOnly:   return "ffmpeg-dl only (fallback/debug)"
        }
    }
}
