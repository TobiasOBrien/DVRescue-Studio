import SwiftUI

struct InstallView: View {
    @EnvironmentObject var toolManager: ToolManager
    @State private var expandedTool: String?
    @State private var showHomebrewInstructions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Install Tools")
                    .font(.largeTitle.bold())
                Text("DVRescue Studio requires three command-line tools installed via Homebrew.")
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 16)

            Divider()

            // Homebrew status
            homebrewBanner

            Divider()

            // Tool table
            toolTable

            Spacer()
        }
        .navigationTitle("Install")
    }

    // MARK: - Homebrew Banner

    private var homebrewBanner: some View {
        HStack(spacing: 12) {
            if let brew = toolManager.homebrewPath {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homebrew found")
                        .fontWeight(.medium)
                    Text(brew)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Homebrew not found")
                        .fontWeight(.medium)
                    Text("Install Homebrew first, then return here to install the tools.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Button("Show Install Instructions") { showHomebrewInstructions.toggle() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            Spacer()
            Button("Refresh") {
                Task { await toolManager.checkAllTools() }
            }
            .disabled(toolManager.isChecking)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .sheet(isPresented: $showHomebrewInstructions) {
            HomebrewInstructionsSheet()
        }
    }

    // MARK: - Tool Table

    private var toolTable: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack {
                Text("Tool")     .frame(width: 130, alignment: .leading)
                Text("Tap")      .frame(width: 220, alignment: .leading)
                Text("Version")  .frame(width: 100, alignment: .leading)
                Text("Status")   .frame(width: 160, alignment: .leading)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            Divider()

            ForEach(toolManager.tools.indices, id: \.self) { idx in
                toolRow(idx: idx)
                if idx < toolManager.tools.count - 1 { Divider() }
            }
        }
    }

    @ViewBuilder
    private func toolRow(idx: Int) -> some View {
        let tool = toolManager.tools[idx]
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Name
                HStack(spacing: 6) {
                    Image(systemName: tool.status.isInstalled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(tool.status.isInstalled ? .green : .secondary)
                    Text(tool.displayName)
                        .fontWeight(.medium)
                        .font(.system(.body, design: .monospaced))
                }
                .frame(width: 130, alignment: .leading)

                // Tap
                Text(tool.brewTap ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 220, alignment: .leading)

                // Version
                Group {
                    if case .installed(let v) = tool.status {
                        Text(v).font(.system(.caption, design: .monospaced))
                    } else if case .checking = tool.status {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 100, alignment: .leading)

                // Status badge
                statusBadge(tool.status)
                    .frame(width: 160, alignment: .leading)

                Spacer()

                // Action
                actionButton(tool: tool, idx: idx)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            // Install log (expanded)
            if expandedTool == tool.id, !toolManager.tools[idx].installLog.isEmpty {
                ScrollView {
                    Text(toolManager.tools[idx].installLog.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 200)
                .background(Color(nsColor: .textBackgroundColor))
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
    }

    private func statusBadge(_ status: ToolInstallStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .installed:    return ("Installed", .green)
            case .notInstalled: return ("Not Installed", .red)
            case .checking:     return ("Checking…", .yellow)
            case .installing:   return ("Installing…", .blue)
            case .failed:       return ("Failed", .red)
            }
        }()

        return Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func actionButton(tool: ToolInfo, idx: Int) -> some View {
        switch tool.status {
        case .notInstalled, .failed:
            Button("Install") {
                guard toolManager.homebrewPath != nil else {
                    showHomebrewInstructions = true
                    return
                }
                expandedTool = tool.id
                Task {
                    await toolManager.installTool(id: tool.id) { line in
                        DispatchQueue.main.async {
                            self.toolManager.tools[idx].installLog.append(line)
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(toolManager.homebrewPath == nil)

        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Button("Log") { expandedTool = expandedTool == tool.id ? nil : tool.id }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }

        case .installed:
            Button("Log") { expandedTool = expandedTool == tool.id ? nil : tool.id }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .opacity(toolManager.tools[idx].installLog.isEmpty ? 0 : 1)

        default:
            EmptyView()
        }
    }
}

// MARK: - Homebrew Instructions Sheet

struct HomebrewInstructionsSheet: View {
    @Environment(\.dismiss) var dismiss
    let installCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Install Homebrew")
                .font(.title2.bold())

            Text("Homebrew is the standard package manager for macOS. Run the following command in Terminal:")
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(installCommand)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installCommand, forType: .string)
                } label: {
                    Label("Copy Command", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)

                Button("Open brew.sh") {
                    NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                }
                .buttonStyle(.bordered)

                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
