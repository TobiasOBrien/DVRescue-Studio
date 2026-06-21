import Foundation

enum TapeHealth {
    case good, warning, poor, analyzing, unknown

    var label: String {
        switch self {
        case .good: return "Good"
        case .warning: return "Warning"
        case .poor: return "Poor"
        case .analyzing: return "Analyzing…"
        case .unknown: return "Unknown"
        }
    }

    var colorName: String {
        switch self {
        case .good: return "green"
        case .warning: return "yellow"
        case .poor: return "red"
        case .analyzing, .unknown: return "gray"
        }
    }
}

struct DVAnalysis {
    var totalFrames: Int = 0
    var errorFrames: Int = 0
    var audioErrors: Int = 0
    var timecodeBreaks: Int = 0
    var dropouts: Int = 0
    var recordingDates: [String] = []
    var duration: TimeInterval = 0
    var isComplete: Bool = false
}

class DVFile: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL

    @Published var fileSize: Int64 = 0
    @Published var captureDate: Date
    @Published var health: TapeHealth = .analyzing
    @Published var analysis = DVAnalysis()
    @Published var thumbnailURL: URL?
    @Published var proxyURL: URL?
    @Published var isAnalyzing: Bool = true
    @Published var isGeneratingProxy: Bool = false

    var tapeLabel: String = ""
    var tapeDescription: String = ""
    var operatorName: String = ""

    var name: String { url.lastPathComponent }

    var thumbURL: URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".thumb.jpg")
    }

    var expectedProxyURL: URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_proxy.mp4")
    }

    init(url: URL) {
        self.url = url
        self.captureDate = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            self.fileSize = size
        }
        if FileManager.default.fileExists(atPath: expectedProxyURL.path) {
            self.proxyURL = expectedProxyURL
        }
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            self.thumbnailURL = thumbURL
        }
        loadSidecar()
    }

    private func loadSidecar() {
        let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
        guard let data = try? Data(contentsOf: jsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        tapeLabel       = json["tapeLabel"] as? String ?? ""
        tapeDescription = json["description"] as? String ?? ""
        operatorName    = json["operatorName"] as? String ?? ""
    }

    func updateHealth() {
        guard analysis.isComplete else { health = .analyzing; return }
        if analysis.errorFrames == 0 && analysis.dropouts == 0 {
            health = .good
        } else if analysis.errorFrames < 10 && analysis.dropouts < 50 {
            health = .warning
        } else {
            health = .poor
        }
    }

    var formattedSize: String {
        let gb = Double(fileSize) / 1_000_000_000
        return gb >= 1 ? String(format: "%.2f GB", gb) : String(format: "%.0f MB", Double(fileSize) / 1_000_000)
    }

    var formattedDuration: String {
        let t = analysis.duration
        let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60; let s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
