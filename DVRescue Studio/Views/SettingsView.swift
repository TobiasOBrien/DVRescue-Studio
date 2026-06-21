import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toolManager: ToolManager

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            captureTab
                .tabItem { Label("Capture", systemImage: "record.circle") }

            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 520, height: 360)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Output") {
                HStack {
                    Text("Output Folder")
                    Spacer()
                    Text(appState.outputFolder.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 220)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.prompt = "Select"
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.outputFolder = url
                            appState.refreshDiskSpace()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack {
                    Text("Filename Prefix")
                    Spacer()
                    TextField("tape", text: $appState.filenamePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                HStack {
                    Text("Filename Pattern")
                    Spacer()
                    Text("\(appState.filenamePrefix)_YYYY-MM-DD_NNN.dv")
                        .foregroundStyle(.secondary)
                        .font(.system(.callout, design: .monospaced))
                }
            }

            Section("Disk Space") {
                HStack {
                    Text("Available")
                    Spacer()
                    Text(String(format: "%.1f GB", appState.availableDiskSpaceGB))
                        .foregroundStyle(appState.availableDiskSpaceGB < 50 ? .yellow : .secondary)
                }
                Text("DV captures approximately 13 GB per hour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Capture Tab

    private var captureTab: some View {
        Form {
            Section("Defaults") {
                Picker("Default Capture Mode", selection: $appState.defaultCaptureMode) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Auto-generate preview proxy after capture", isOn: $appState.autoGenerateProxy)
                Text("Generates a low-res H.264 proxy (640px, CRF 23) in the background after capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tool Paths") {
                ForEach(toolManager.tools) { tool in
                    HStack {
                        Text(tool.displayName)
                            .frame(width: 100, alignment: .leading)
                        Text(tool.resolvedPath ?? "Not installed")
                            .foregroundStyle(tool.resolvedPath != nil ? .secondary : .red)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - Notifications Tab

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Send notification when capture completes", isOn: $appState.notificationsEnabled)
                Text("Includes tape label and file size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Test") {
                Button("Send Test Notification") {
                    NotificationManager.captureComplete(tapeLabel: "Test Tape", fileSize: "4.7 GB")
                }
                .buttonStyle(.bordered)
                .disabled(!appState.notificationsEnabled)
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                Text("DVRescue Studio")
                    .font(.title2.bold())
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                   let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    Text("Version \(version) (\(build))")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Capture, preserve, and analyze DV/MiniDV tapes. Built with dvrescue and ffmpeg.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Button("Check for Updates…") {
                    // Sparkle: SUUpdater.shared()?.checkForUpdates(nil)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
