import Foundation

class ToolManager: ObservableObject {
    static let shared = ToolManager()

    @Published var tools: [ToolInfo] = ToolInfo.all
    @Published var homebrewPath: String?
    @Published var isChecking: Bool = false

    private let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    var allInstalled: Bool { tools.allSatisfy { $0.status.isInstalled } }

    func resolvedPath(for id: String) -> String? {
        tools.first(where: { $0.id == id })?.resolvedPath
    }

    @MainActor
    func checkAllTools() async {
        isChecking = true
        homebrewPath = brewCandidates.first { FileManager.default.fileExists(atPath: $0) }

        for i in tools.indices {
            tools[i].status = .checking
            let path = tools[i].resolvedPath
            if let path {
                let version = await getVersion(path: path, tool: tools[i])
                tools[i].status = .installed(version: version)
            } else {
                tools[i].status = .notInstalled
            }
        }
        isChecking = false
    }

    private func getVersion(path: String, tool: ToolInfo) async -> String {
        let args: [String]
        switch tool.id {
        case "ffmpeg-dl":   args = ["-version"]
        case "dvrescue":    args = ["--version"]
        default:            args = ["--Version"]
        }
        let output = await runCaptured(path: path, args: args)
        return extractVersion(from: output)
    }

    private func extractVersion(from output: String) -> String {
        let line = output.components(separatedBy: "\n").first ?? output
        if let range = line.range(of: #"\d+\.\d+[\.\d]*"#, options: .regularExpression) {
            return String(line[range])
        }
        return "installed"
    }

    @MainActor
    func installTool(id: String, logHandler: @escaping (String) -> Void) async -> Bool {
        guard let idx = tools.firstIndex(where: { $0.id == id }) else { return false }
        guard let brew = homebrewPath ?? brewCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            logHandler("❌ Homebrew not found. Install from https://brew.sh first.")
            return false
        }

        tools[idx].status = .installing
        tools[idx].installLog = []

        if let tap = tools[idx].brewTap {
            logHandler("→ brew tap \(tap)")
            _ = await runBrew(brew, args: ["tap", tap], logHandler: logHandler)
        }

        logHandler("→ brew install \(tools[idx].brewPackage)")
        let success = await runBrew(brew, args: ["install", tools[idx].brewPackage], logHandler: logHandler)

        if success {
            let version = tools[idx].resolvedPath.flatMap { p in
                let out = (try? runSync(path: p, args: ["--version"])) ?? ""
                return extractVersion(from: out)
            } ?? "installed"
            tools[idx].status = .installed(version: version)
            logHandler("✓ \(tools[idx].displayName) installed successfully.")
        } else {
            tools[idx].status = .failed("Install failed — check log")
        }
        return success
    }

    private func runBrew(_ brew: String, args: [String], logHandler: @escaping (String) -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            let p = makeProcess(path: brew, args: args)
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
                for line in s.components(separatedBy: "\n") where !line.isEmpty {
                    DispatchQueue.main.async { logHandler(line) }
                }
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            do { try p.run() } catch { continuation.resume(returning: false) }
        }
    }

    private func runCaptured(path: String, args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let p = makeProcess(path: path, args: args)
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do { try p.run() } catch { continuation.resume(returning: "") }
        }
    }

    private func runSync(path: String, args: [String]) throws -> String {
        let p = makeProcess(path: path, args: args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func makeProcess(path: String, args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        return p
    }
}
