import Foundation

enum ToolInstallStatus: Equatable {
    case checking
    case installed(version: String)
    case notInstalled
    case installing
    case failed(String)

    var label: String {
        switch self {
        case .checking: return "Checking…"
        case .installed(let v): return "Installed (\(v))"
        case .notInstalled: return "Not Installed"
        case .installing: return "Installing…"
        case .failed(let e): return "Failed: \(e)"
        }
    }

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

struct ToolInfo: Identifiable {
    let id: String
    let displayName: String
    let brewPackage: String
    let brewTap: String?
    let candidatePaths: [String]
    var status: ToolInstallStatus = .checking
    var installLog: [String] = []

    var resolvedPath: String? {
        candidatePaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    static let ffmpegDL = ToolInfo(
        id: "ffmpeg-dl",
        displayName: "ffmpeg-dl",
        brewPackage: "ffmpeg-dl",
        brewTap: "amiaopensource/amiaopensource",
        candidatePaths: ["/opt/homebrew/bin/ffmpeg-dl", "/usr/local/bin/ffmpeg-dl"]
    )

    static let dvrescue = ToolInfo(
        id: "dvrescue",
        displayName: "dvrescue",
        brewPackage: "dvrescue",
        brewTap: "mediaarea/mediaarea",
        candidatePaths: ["/opt/homebrew/bin/dvrescue", "/usr/local/bin/dvrescue"]
    )

    static let mediainfo = ToolInfo(
        id: "mediainfo",
        displayName: "mediainfo",
        brewPackage: "mediainfo",
        brewTap: "mediaarea/mediaarea",
        candidatePaths: ["/opt/homebrew/bin/mediainfo", "/usr/local/bin/mediainfo"]
    )

    static var all: [ToolInfo] { [.ffmpegDL, .dvrescue, .mediainfo] }
}
