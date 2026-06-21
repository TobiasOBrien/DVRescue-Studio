import Foundation

enum QueueItemStatus: Equatable {
    case waiting, capturing, completed, failed(String)
    var label: String {
        switch self {
        case .waiting: return "Waiting"
        case .capturing: return "Capturing…"
        case .completed: return "Completed"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
}

class CaptureQueueItem: ObservableObject, Identifiable {
    let id = UUID()
    @Published var tapeLabel: String
    @Published var description: String
    @Published var operatorName: String
    @Published var estimatedMinutes: Int
    @Published var videoStandard: VideoStandard
    @Published var status: QueueItemStatus = .waiting
    @Published var outputURL: URL?

    init(tapeLabel: String = "Tape \(Int.random(in: 1...999))",
         description: String = "",
         operatorName: String = "",
         estimatedMinutes: Int = 60,
         videoStandard: VideoStandard = .ntsc) {
        self.tapeLabel = tapeLabel
        self.description = description
        self.operatorName = operatorName
        self.estimatedMinutes = estimatedMinutes
        self.videoStandard = videoStandard
    }

    var estimatedSizeGB: Double { Double(estimatedMinutes) / 60.0 * 13.0 }

    var estimatedSizeLabel: String { String(format: "~%.1f GB", estimatedSizeGB) }
}
