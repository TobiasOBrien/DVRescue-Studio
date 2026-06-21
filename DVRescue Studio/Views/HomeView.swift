import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toolManager: ToolManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                hardwareChecklist
                toolStatusSection
                diskSpaceSection
                recentCapturesSection
            }
            .padding(24)
        }
        .navigationTitle("DVRescue Studio")
        .onAppear { appState.refreshDiskSpace() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DVRescue Studio")
                .font(.largeTitle.bold())
            Text("Capture, preserve, and analyze DV/MiniDV tapes from FireWire camcorders.")
                .foregroundStyle(.secondary)
        }
    }

    private var hardwareChecklist: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hardware Required")
                    .font(.headline)
                    .padding(.bottom, 2)

                HStack(spacing: 0) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .padding(.trailing, 8)
                    Text("FireWire DV capture requires a physical connection chain most modern Macs lack by default.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                hardwareRow(icon: "cable.connector", label: "Thunderbolt → FireWire 800 adapter")
                hardwareRow(icon: "cable.connector.horizontal", label: "FireWire 800 → FireWire 400 cable (if needed for older camcorders)")
                hardwareRow(icon: "video", label: "DV camcorder or VTR with DV/MiniDV output")

                Text("Devices appear in AVFoundation (e.g. \"PV-GS35\") once connected and powered on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(8)
        }
    }

    private func hardwareRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.blue)
            Text(label)
        }
    }

    private var toolStatusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tool Status")
                        .font(.headline)
                    Spacer()
                    if toolManager.isChecking {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.bottom, 2)

                ForEach(toolManager.tools) { tool in
                    HStack {
                        Circle()
                            .fill(statusColor(tool.status))
                            .frame(width: 10, height: 10)
                        Text(tool.displayName)
                            .frame(width: 100, alignment: .leading)
                        Text(tool.status.label)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                    }
                }

                if !toolManager.allInstalled {
                    Button("Go to Install Screen") {
                        appState.pendingNavigation = .install
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(8)
        }
    }

    private var diskSpaceSection: some View {
        GroupBox {
            HStack {
                Image(systemName: appState.availableDiskSpaceGB < 50 ? "exclamationmark.triangle.fill" : "internaldrive")
                    .foregroundStyle(appState.availableDiskSpaceGB < 50 ? .yellow : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output Disk Space")
                        .font(.headline)
                    Text("\(String(format: "%.1f", appState.availableDiskSpaceGB)) GB free on output volume")
                        .foregroundStyle(appState.availableDiskSpaceGB < 50 ? .yellow : .secondary)
                        .font(.callout)
                    if appState.availableDiskSpaceGB < 50 {
                        Text("Warning: Less than 50 GB free. DV captures ~13 GB/hour.")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
                Spacer()
                Text(appState.outputFolder.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(8)
        }
    }

    private var recentCapturesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Captures")
                        .font(.headline)
                    Spacer()
                    Button("View Library") { appState.pendingNavigation = .library }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
                .padding(.bottom, 2)

                if appState.recentCaptures.isEmpty {
                    Text("No captures yet. Head to the Capture screen to get started.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(appState.recentCaptures) { capture in
                        HStack {
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(capture.displayName)
                                    .fontWeight(.medium)
                                Text(capture.url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(formatDate(capture.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        if capture.id != appState.recentCaptures.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: ToolInstallStatus) -> Color {
        switch status {
        case .installed: return .green
        case .notInstalled, .failed: return .red
        case .checking, .installing: return .yellow
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
