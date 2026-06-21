import Foundation
import Combine

class CaptureManager: ObservableObject {
    static let shared = CaptureManager()

    @Published var session = CaptureSession()
    @Published var availableDevices: [String] = []
    @Published var isDetectingDevices: Bool = false

    private var ffmpegProcess: Process?
    private var teeProcess: Process?
    private var dvrescueProcess: Process?
    private var xmlParser = DVRescueXMLParser()
    private var elapsedTimer: Timer?
    private var sizeTimer: Timer?
    private var prevFileSize: Int64 = 0

    // MARK: - Device Detection

    func detectDevices() {
        isDetectingDevices = true
        Task {
            let devices = await listAVFoundationDevices()
            await MainActor.run {
                self.availableDevices = devices
                self.isDetectingDevices = false
            }
        }
    }

    private func listAVFoundationDevices() async -> [String] {
        guard let path = ToolManager.shared.resolvedPath(for: "ffmpeg-dl") else { return [] }

        return await withCheckedContinuation { continuation in
            let p = makeProcess(path: path, args: ["-f", "avfoundation", "-list_devices", "true", "-i", ""])
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = FileHandle.nullDevice

            var output = ""
            errPipe.fileHandleForReading.readabilityHandler = { h in
                if let s = String(data: h.availableData, encoding: .utf8) { output += s }
            }

            p.terminationHandler = { [weak self] _ in
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: self?.parseDeviceNames(from: output) ?? [])
            }

            do {
                try p.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                    if p.isRunning { p.terminate() }
                }
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func parseDeviceNames(from stderr: String) -> [String] {
        var devices: [String] = []
        var inVideo = false

        for line in stderr.components(separatedBy: "\n") {
            if line.contains("AVFoundation video devices") { inVideo = true; continue }
            if line.contains("AVFoundation audio devices") { inVideo = false; continue }
            guard inVideo else { continue }

            // Match: [0] DeviceName  or  [AVFoundation indev @ ...] [0] DeviceName
            let pattern = #"\[(\d+)\]\s+(.+)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let nameRange = Range(m.range(at: 2), in: line) {
                let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { devices.append(name) }
            }
        }
        return devices
    }

    // MARK: - Capture

    func startCapture(
        deviceName: String,
        outputURL: URL,
        mode: CaptureMode,
        videoStandard: VideoStandard,
        splitOnTimecodeBreak: Bool,
        tapeLabel: String,
        description: String,
        operatorName: String
    ) throws {
        guard !session.isActive else { throw CaptureError.alreadyCapturing }

        session = CaptureSession()
        session.outputURL = outputURL
        session.deviceName = deviceName
        session.tapeLabel = tapeLabel
        session.state = .starting

        writeSidecar(outputURL: outputURL, tapeLabel: tapeLabel, description: description, operatorName: operatorName)

        xmlParser.reset()
        xmlParser.onUpdate = { [weak self] media in
            guard let s = self?.session else { return }
            DispatchQueue.main.async {
                s.frameCount         = media.totalFrames
                s.dropoutCount       = media.dropouts
                s.errorFrameCount    = media.errorFrames
                s.audioErrorCount    = media.audioErrors
                s.timecodeBreakCount = media.timecodeBreaks
                if !media.lastTimecode.isEmpty { s.timecode = media.lastTimecode }
            }
        }

        switch mode {
        case .dvrescuePipe: try launchPipeline(deviceName: deviceName, outputURL: outputURL)
        case .ffmpegOnly:   try launchFFmpegOnly(deviceName: deviceName, outputURL: outputURL)
        }

        session.startTime = Date()
        startTimers()

        DispatchQueue.main.async { self.session.state = .capturing }
    }

    // Three-process pipeline: ffmpeg-dl | tee outputFile | dvrescue -
    private func launchPipeline(deviceName: String, outputURL: URL) throws {
        guard let ffmpegPath = ToolManager.shared.resolvedPath(for: "ffmpeg-dl"),
              let dvrescuePath = ToolManager.shared.resolvedPath(for: "dvrescue") else {
            throw CaptureError.toolNotFound("ffmpeg-dl or dvrescue")
        }

        // Process 1 — ffmpeg-dl
        let ffmpeg = makeProcess(path: ffmpegPath, args: [
            "-f", "avfoundation",
            "-capture_raw_data", "true",
            "-i", deviceName,
            "-c", "copy",
            "-f", "dv", "-"
        ])
        let ffmpegToTee = Pipe()
        ffmpeg.standardOutput = ffmpegToTee
        let ffmpegErr = Pipe()
        ffmpeg.standardError = ffmpegErr

        // Process 2 — tee
        let tee = makeProcess(path: "/usr/bin/tee", args: [outputURL.path])
        tee.standardInput = ffmpegToTee
        let teeToRescue = Pipe()
        tee.standardOutput = teeToRescue

        // Process 3 — dvrescue
        let dvrescue = makeProcess(path: dvrescuePath, args: ["-"])
        dvrescue.standardInput = teeToRescue
        let rescueOut = Pipe()
        dvrescue.standardOutput = rescueOut
        dvrescue.standardError = FileHandle.nullDevice

        // Read ffmpeg stderr → log
        ffmpegErr.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let s = String(data: h.availableData, encoding: .utf8) else { return }
            for line in s.components(separatedBy: "\n") { self?.session.appendLog(line) }
        }

        // Read dvrescue stdout → XML parser
        rescueOut.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if !data.isEmpty { self?.xmlParser.feed(data: data) }
        }

        ffmpeg.terminationHandler    = { [weak self] _ in self?.handleTermination() }
        dvrescue.terminationHandler  = { _ in } // cleanup handled above

        try ffmpeg.run()
        try tee.run()
        try dvrescue.run()

        self.ffmpegProcess   = ffmpeg
        self.teeProcess      = tee
        self.dvrescueProcess = dvrescue
    }

    // Fallback: ffmpeg-dl writes directly to file, no dvrescue analysis
    private func launchFFmpegOnly(deviceName: String, outputURL: URL) throws {
        guard let ffmpegPath = ToolManager.shared.resolvedPath(for: "ffmpeg-dl") else {
            throw CaptureError.toolNotFound("ffmpeg-dl")
        }

        let ffmpeg = makeProcess(path: ffmpegPath, args: [
            "-f", "avfoundation",
            "-capture_raw_data", "true",
            "-i", deviceName,
            "-c", "copy",
            outputURL.path
        ])
        let errPipe = Pipe()
        ffmpeg.standardError = errPipe
        ffmpeg.standardOutput = FileHandle.nullDevice

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let s = String(data: h.availableData, encoding: .utf8) else { return }
            for line in s.components(separatedBy: "\n") { self?.session.appendLog(line) }
        }

        ffmpeg.terminationHandler = { [weak self] _ in self?.handleTermination() }
        try ffmpeg.run()
        self.ffmpegProcess = ffmpeg
    }

    private func handleTermination() {
        DispatchQueue.main.async {
            self.stopTimers()
            self.xmlParser.finalize()
            let code = self.ffmpegProcess?.terminationStatus ?? 0
            // SIGINT exit code on macOS is 2
            if code == 0 || code == 2 {
                self.session.state = .finished
            } else {
                self.session.state = .error("Process exited with status \(code)")
            }
        }
    }

    func stopCapture() {
        session.state = .stopping
        // SIGINT → each process flushes and closes cleanly
        ffmpegProcess?.interrupt()
        teeProcess?.interrupt()
        dvrescueProcess?.interrupt()
        // Force-kill after 5 s if not yet exited
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.ffmpegProcess?.terminate()
            self?.teeProcess?.terminate()
            self?.dvrescueProcess?.terminate()
        }
    }

    // MARK: - Proxy Generation

    func generateProxy(for dvURL: URL) {
        guard let ffmpegPath = ToolManager.shared.resolvedPath(for: "ffmpeg-dl") else { return }
        let proxyURL = dvURL.deletingLastPathComponent()
            .appendingPathComponent(dvURL.deletingPathExtension().lastPathComponent + "_proxy.mp4")

        DispatchQueue.global(qos: .utility).async {
            let p = self.makeProcess(path: ffmpegPath, args: [
                "-i", dvURL.path,
                "-c:v", "libx264", "-crf", "23", "-preset", "fast",
                "-vf", "scale=640:-2",
                "-c:a", "aac", "-b:a", "128k",
                proxyURL.path
            ])
            p.standardOutput = FileHandle.nullDevice
            p.standardError  = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    // MARK: - Timers

    private func startTimers() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let s = self?.session.startTime else { return }
            DispatchQueue.main.async { self?.session.elapsedTime = Date().timeIntervalSince(s) }
        }

        sizeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let url = self?.session.outputURL,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64 else { return }
            let prev = self?.prevFileSize ?? 0
            DispatchQueue.main.async {
                self?.session.fileSizeBytes = size
                self?.session.captureSpeedMBps = Double(size - prev) / 2.0 / 1_000_000
                self?.prevFileSize = size
            }
        }
    }

    private func stopTimers() {
        elapsedTimer?.invalidate(); elapsedTimer = nil
        sizeTimer?.invalidate();    sizeTimer = nil
    }

    // MARK: - Helpers

    private func makeProcess(path: String, args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        return p
    }

    private func writeSidecar(outputURL: URL, tapeLabel: String, description: String, operatorName: String) {
        let jsonURL = outputURL.deletingPathExtension().appendingPathExtension("json")
        let payload: [String: Any] = [
            "tapeLabel": tapeLabel,
            "description": description,
            "operatorName": operatorName,
            "captureDate": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? data.write(to: jsonURL)
        }
    }
}

enum CaptureError: LocalizedError {
    case alreadyCapturing
    case toolNotFound(String)
    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:      return "A capture is already in progress."
        case .toolNotFound(let t):   return "Required tool not found: \(t)"
        }
    }
}
