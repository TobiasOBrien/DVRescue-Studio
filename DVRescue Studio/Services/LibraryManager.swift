import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case h264   = "H.264 (Web)"
    case prores = "ProRes (Archival)"
    var id: String { rawValue }
    var ext: String { self == .h264 ? "mp4" : "mov" }
}

class LibraryManager: ObservableObject {
    @Published var files: [DVFile] = []
    @Published var isScanning: Bool = false
    @Published var selectedFile: DVFile?

    private var scanTask: Task<Void, Never>?

    func scan(folder: URL) {
        scanTask?.cancel()
        scanTask = Task {
            await MainActor.run { self.isScanning = true; self.files = [] }

            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                await MainActor.run { self.isScanning = false }
                return
            }

            var dvFiles: [DVFile] = []
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "dv" {
                dvFiles.append(DVFile(url: url))
            }
            dvFiles.sort { $0.captureDate > $1.captureDate }

            await MainActor.run { self.files = dvFiles; self.isScanning = false }

            // Background analysis
            for file in dvFiles {
                if Task.isCancelled { break }
                await analyzeFile(file)
                await generateThumbnail(for: file)
            }
        }
    }

    private func analyzeFile(_ file: DVFile) async {
        guard let dvrescuePath = ToolManager.shared.resolvedPath(for: "dvrescue") else {
            await MainActor.run { file.health = .unknown; file.isAnalyzing = false }
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: dvrescuePath)
            p.arguments = [file.url.path]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env

            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = FileHandle.nullDevice

            var xmlData = Data()
            pipe.fileHandleForReading.readabilityHandler = { h in xmlData.append(h.availableData) }

            p.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                let parser = DVRescueXMLParser()
                parser.feed(data: xmlData)
                parser.finalize()
                DispatchQueue.main.async {
                    file.analysis.errorFrames    = parser.media.errorFrames
                    file.analysis.audioErrors    = parser.media.audioErrors
                    file.analysis.timecodeBreaks = parser.media.timecodeBreaks
                    file.analysis.dropouts       = parser.media.dropouts
                    file.analysis.recordingDates = parser.media.recordingDates
                    file.analysis.totalFrames    = parser.media.totalFrames
                    file.analysis.duration       = parser.media.duration
                    file.analysis.isComplete     = true
                    file.isAnalyzing             = false
                    file.updateHealth()
                }
                cont.resume()
            }
            do { try p.run() } catch {
                DispatchQueue.main.async { file.health = .unknown; file.isAnalyzing = false }
                cont.resume()
            }
        }
    }

    private func generateThumbnail(for file: DVFile) async {
        guard file.thumbnailURL == nil,
              let ffmpegPath = ToolManager.shared.resolvedPath(for: "ffmpeg-dl") else { return }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffmpegPath)
            p.arguments = ["-i", file.url.path,
                           "-vf", "select=eq(pict_type\\,I)", "-vframes", "1",
                           "-f", "image2", file.thumbURL.path]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError  = FileHandle.nullDevice

            p.terminationHandler = { _ in
                if FileManager.default.fileExists(atPath: file.thumbURL.path) {
                    DispatchQueue.main.async { file.thumbnailURL = file.thumbURL }
                }
                cont.resume()
            }
            try? p.run()
        }
    }

    // MARK: - Export

    func export(file: DVFile, format: ExportFormat, to destination: URL) {
        guard let ffmpegPath = ToolManager.shared.resolvedPath(for: "ffmpeg-dl") else { return }

        let args: [String]
        switch format {
        case .h264:
            args = ["-i", file.url.path, "-c:v", "libx264", "-crf", "18", "-preset", "medium",
                    "-c:a", "aac", "-b:a", "192k", destination.path]
        case .prores:
            args = ["-i", file.url.path, "-c:v", "prores_ks", "-profile:v", "3",
                    "-c:a", "pcm_s16le", destination.path]
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffmpegPath)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError  = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    // MARK: - Tape Condition Report

    func tapeConditionReport(for file: DVFile) -> String {
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .short
        return """
        Tape Condition Report
        =====================
        Tape Label:      \(file.tapeLabel.isEmpty ? "(untitled)" : file.tapeLabel)
        Capture Date:    \(fmt.string(from: file.captureDate))
        Duration:        \(file.formattedDuration)
        File Size:       \(file.formattedSize)
        File:            \(file.url.lastPathComponent)
        Operator:        \(file.operatorName.isEmpty ? "—" : file.operatorName)

        Health Assessment
        -----------------
        Overall Health:  \(file.health.label)
        Total Frames:    \(file.analysis.totalFrames)
        Error Frames:    \(file.analysis.errorFrames)
        Audio Errors:    \(file.analysis.audioErrors)
        Timecode Breaks: \(file.analysis.timecodeBreaks)
        Dropouts:        \(file.analysis.dropouts)
        \(file.analysis.recordingDates.isEmpty ? "" : "\nRecording Dates on Tape\n-----------------------\n" + file.analysis.recordingDates.joined(separator: "\n"))
        \(file.tapeDescription.isEmpty ? "" : "\nDescription: \(file.tapeDescription)")
        """
    }
}
