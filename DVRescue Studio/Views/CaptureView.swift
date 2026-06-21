import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var captureManager: CaptureManager
    @EnvironmentObject var toolManager: ToolManager
    @EnvironmentObject var menuBarManager: MenuBarManager

    // Setup state
    @State private var selectedDevice: String = ""
    @State private var videoStandard: VideoStandard = .ntsc
    @State private var captureMode: CaptureMode = .dvrescuePipe
    @State private var splitOnTimecodeBreak: Bool = false
    @State private var tapeLabel: String = ""
    @State private var tapeDescription: String = ""
    @State private var operatorName: String = ""
    @State private var estimatedMinutes: Int = 60
    @State private var showLog: Bool = false
    @State private var alertMessage: String?
    @State private var showAlert: Bool = false

    // Capture queue
    @State private var captureQueue: [CaptureQueueItem] = []
    @State private var showQueue: Bool = false

    private var session: CaptureSession { captureManager.session }
    private var isCapturing: Bool { session.state == .capturing || session.state == .starting }

    var body: some View {
        HStack(spacing: 0) {
            // Main column
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    if !toolManager.allInstalled {
                        toolsWarning
                    }
                    deviceSection
                    outputSection
                    optionsSection
                    metadataSection
                    diskEstimateSection
                    Divider()
                    captureControls
                    if isCapturing || session.state == .finished || session.state == .stopping {
                        progressSection
                    }
                }
                .padding(24)
            }

            // Queue sidebar (toggleable)
            if showQueue {
                Divider()
                captureQueuePanel
                    .frame(width: 260)
            }
        }
        .navigationTitle("Capture")
        .toolbar {
            ToolbarItem {
                Button {
                    showQueue.toggle()
                } label: {
                    Label("Queue", systemImage: "list.number")
                }
                .help("Toggle Capture Queue")
            }
        }
        .onAppear {
            captureMode = appState.defaultCaptureMode
            captureManager.detectDevices()
        }
        .alert("Capture Error", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: session.state) { _, state in
            handleStateChange(state)
        }
    }

    // MARK: - Sections

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture")
                .font(.largeTitle.bold())
            Text("Connect your FireWire DV device, select it below, then press Start.")
                .foregroundStyle(.secondary)
        }
    }

    private var toolsWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Some required tools are missing.")
            Spacer()
            Button("Install Tools") { appState.pendingNavigation = .install }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(8)
    }

    private var deviceSection: some View {
        GroupBox("DV Device") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if captureManager.isDetectingDevices {
                        ProgressView().controlSize(.small)
                        Text("Detecting devices…").foregroundStyle(.secondary)
                    } else if captureManager.availableDevices.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                            Text("No DV devices found. Check your FireWire connection.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Device", selection: $selectedDevice) {
                            Text("Select a device…").tag("")
                            ForEach(captureManager.availableDevices, id: \.self) { device in
                                Text(device).tag(device)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }
                    Spacer()
                    Button {
                        captureManager.detectDevices()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(captureManager.isDetectingDevices || isCapturing)
                }
                .padding(8)
            }
        }
    }

    private var outputSection: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Folder:")
                        .frame(width: 80, alignment: .trailing)
                    Text(appState.outputFolder.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.prompt = "Select Output Folder"
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.outputFolder = url
                            appState.refreshDiskSpace()
                        }
                    }
                    .controlSize(.small)
                    .disabled(isCapturing)
                }
                HStack {
                    Text("File:")
                        .frame(width: 80, alignment: .trailing)
                    Text(appState.nextOutputURL().lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var optionsSection: some View {
        GroupBox("Options") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Video Standard").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $videoStandard) {
                            ForEach(VideoStandard.allCases) { s in Text(s.rawValue).tag(s) }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Capture Mode").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $captureMode) {
                            ForEach(CaptureMode.allCases, id: \.self) { m in Text(m.displayName).tag(m) }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                }

                Toggle("Split on timecode break", isOn: $splitOnTimecodeBreak)
                    .disabled(captureMode == .ffmpegOnly)
                if captureMode == .ffmpegOnly {
                    Text("Split on timecode break requires dvrescue pipe mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .disabled(isCapturing)
        }
    }

    private var metadataSection: some View {
        GroupBox("Tape Metadata") {
            VStack(alignment: .leading, spacing: 10) {
                labeledField("Label", text: $tapeLabel, placeholder: "e.g. Family Vacation 2001")
                labeledField("Description", text: $tapeDescription, placeholder: "Optional notes")
                labeledField("Operator", text: $operatorName, placeholder: "Your name")
            }
            .padding(8)
            .disabled(isCapturing)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label + ":")
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
        }
    }

    private var diskEstimateSection: some View {
        GroupBox("Disk Estimate") {
            HStack(spacing: 20) {
                HStack {
                    Text("Tape length (min):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $estimatedMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                let estimatedGB = Double(estimatedMinutes) / 60.0 * 13.0
                Text("≈ \(String(format: "%.1f", estimatedGB)) GB needed")
                    .foregroundStyle(.secondary)
                if estimatedGB > appState.availableDiskSpaceGB {
                    Label("Insufficient disk space!", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding(8)
            .disabled(isCapturing)
        }
    }

    private var captureControls: some View {
        HStack(spacing: 16) {
            if !isCapturing {
                Button {
                    startCapture()
                } label: {
                    Label("Start Capture", systemImage: "record.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(!canStartCapture)
            } else {
                Button {
                    captureManager.stopCapture()
                } label: {
                    Label("Stop Capture", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.primary)
            }

            if let error = captureStateError {
                Label(error, systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            }
        }
    }

    private var captureStateError: String? {
        if case .error(let msg) = session.state { return msg }
        return nil
    }

    // MARK: - Live Progress

    private var progressSection: some View {
        GroupBox("Live Progress") {
            VStack(alignment: .leading, spacing: 16) {
                // Primary stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCell("Elapsed", session.formattedElapsed)
                    statCell("Frames", "\(session.frameCount)")
                    statCell("Timecode", session.timecode)
                    statCell("File Size", session.formattedFileSize)
                    statCell("Speed", String(format: "%.1f MB/s", session.captureSpeedMBps))
                    statCell("State", stateLabel(session.state))
                }

                // Health indicators (dvrescue pipe mode only)
                if captureMode == .dvrescuePipe {
                    Divider()
                    HStack(spacing: 24) {
                        healthCell("Dropouts", "\(session.dropoutCount)", session.dropoutCount > 0 ? .yellow : .green)
                        healthCell("Error Frames", "\(session.errorFrameCount)", session.errorFrameCount > 0 ? .red : .green)
                        healthCell("Audio Errors", "\(session.audioErrorCount)", session.audioErrorCount > 0 ? .yellow : .green)
                        healthCell("TC Breaks", "\(session.timecodeBreakCount)", session.timecodeBreakCount > 0 ? .orange : .green)
                    }
                }

                // Log
                Divider()
                DisclosureGroup("ffmpeg-dl Log (\(session.logLines.count) lines)", isExpanded: $showLog) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(session.logLines.enumerated()), id: \.offset) { i, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .id(i)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 160)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .onChange(of: session.logLines.count) { _, count in
                            proxy.scrollTo(count - 1)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func healthCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Capture Queue Panel

    private var captureQueuePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Capture Queue")
                    .font(.headline)
                    .padding()
                Spacer()
                Button { captureQueue.append(CaptureQueueItem()) } label: {
                    Image(systemName: "plus")
                }
                .padding(.trailing)
            }

            Divider()

            if captureQueue.isEmpty {
                Text("Add tapes to queue for sequential capture.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding()
            } else {
                let totalMinutes = captureQueue.filter { $0.status == .waiting }.reduce(0) { $0 + $1.estimatedMinutes }
                Text("Total remaining: ~\(totalMinutes) min (\(String(format: "%.1f", Double(totalMinutes)/60.0*13)) GB)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)

                List {
                    ForEach(captureQueue) { item in
                        queueRow(item)
                    }
                    .onDelete { captureQueue.remove(atOffsets: $0) }
                    .onMove { captureQueue.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
            }

            Divider()
            Button("Next Tape") {
                advanceQueue()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCapturing || captureQueue.filter { $0.status == .waiting }.isEmpty)
            .padding()
        }
    }

    private func queueRow(_ item: CaptureQueueItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.tapeLabel).fontWeight(.medium)
                Text("\(item.estimatedMinutes) min · \(item.estimatedSizeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Logic

    private var canStartCapture: Bool {
        !selectedDevice.isEmpty && toolManager.allInstalled && session.state != .capturing
    }

    private func startCapture() {
        let outputURL = appState.nextOutputURL()
        do {
            try captureManager.startCapture(
                deviceName: selectedDevice,
                outputURL: outputURL,
                mode: captureMode,
                videoStandard: videoStandard,
                splitOnTimecodeBreak: splitOnTimecodeBreak,
                tapeLabel: tapeLabel,
                description: tapeDescription,
                operatorName: operatorName
            )
            menuBarManager.startShowing(session: captureManager.session)
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func advanceQueue() {
        guard let next = captureQueue.first(where: { $0.status == .waiting }) else { return }
        tapeLabel     = next.tapeLabel
        tapeDescription = next.description
        operatorName  = next.operatorName
        videoStandard = next.videoStandard
        estimatedMinutes = next.estimatedMinutes
        next.status   = .capturing
        startCapture()
    }

    private func handleStateChange(_ state: CaptureState) {
        switch state {
        case .finished:
            menuBarManager.stopShowing()
            if let url = session.outputURL {
                appState.addRecentCapture(url: url, tapeLabel: session.tapeLabel)
                if appState.notificationsEnabled {
                    NotificationManager.captureComplete(tapeLabel: session.tapeLabel, fileSize: session.formattedFileSize)
                }
                if appState.autoGenerateProxy {
                    captureManager.generateProxy(for: url)
                }
                // Mark queue item complete
                if let idx = captureQueue.firstIndex(where: { $0.status == .capturing }) {
                    captureQueue[idx].status = .completed
                    captureQueue[idx].outputURL = url
                }
            }
        case .error(let msg):
            menuBarManager.stopShowing()
            alertMessage = msg
            showAlert = true
            if let idx = captureQueue.firstIndex(where: { $0.status == .capturing }) {
                captureQueue[idx].status = .failed(msg)
            }
        default:
            break
        }
    }

    private func stateLabel(_ state: CaptureState) -> String {
        switch state {
        case .idle:       return "Idle"
        case .starting:   return "Starting…"
        case .capturing:  return "● Capturing"
        case .paused:     return "Paused"
        case .stopping:   return "Stopping…"
        case .finished:   return "Finished"
        case .error:      return "Error"
        }
    }
}
