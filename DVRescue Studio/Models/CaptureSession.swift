import Foundation

enum CaptureState: Equatable {
    case idle
    case starting
    case capturing
    case paused
    case stopping
    case finished
    case error(String)
}

enum VideoStandard: String, CaseIterable, Identifiable {
    case ntsc = "NTSC"
    case pal  = "PAL"
    var id: String { rawValue }
    var fps: Double { self == .ntsc ? 29.97 : 25.0 }
}

class CaptureSession: ObservableObject {
    @Published var state: CaptureState = .idle
    @Published var frameCount: Int = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timecode: String = "--:--:--:--"
    @Published var fileSizeBytes: Int64 = 0
    @Published var captureSpeedMBps: Double = 0
    @Published var dropoutCount: Int = 0
    @Published var errorFrameCount: Int = 0
    @Published var audioErrorCount: Int = 0
    @Published var timecodeBreakCount: Int = 0
    @Published var logLines: [String] = []

    var outputURL: URL?
    var deviceName: String = ""
    var tapeLabel: String = ""
    var startTime: Date?

    var isActive: Bool {
        switch state {
        case .starting, .capturing, .paused, .stopping: return true
        default: return false
        }
    }

    var formattedElapsed: String {
        let h = Int(elapsedTime) / 3600
        let m = (Int(elapsedTime) % 3600) / 60
        let s = Int(elapsedTime) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    var formattedFileSize: String {
        let gb = Double(fileSizeBytes) / 1_000_000_000
        return gb >= 1 ? String(format: "%.2f GB", gb) : String(format: "%.0f MB", Double(fileSizeBytes) / 1_000_000)
    }

    func appendLog(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        DispatchQueue.main.async {
            self.logLines.append(line)
            if self.logLines.count > 2000 {
                self.logLines.removeFirst(self.logLines.count - 2000)
            }
        }
    }
}
