import SwiftUI
import AVKit

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var searchText: String = ""
    @State private var exportFormat: ExportFormat = .h264
    @State private var showExportPanel: Bool = false
    @State private var showReportSheet: Bool = false
    @State private var reportContent: String = ""

    private var filteredFiles: [DVFile] {
        if searchText.isEmpty { return libraryManager.files }
        return libraryManager.files.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tapeLabel.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            fileList
                .frame(minWidth: 280, idealWidth: 320)

            detailPanel
                .frame(minWidth: 460)
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                Button {
                    libraryManager.scan(folder: appState.outputFolder)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Re-scan output folder")
            }
        }
        .onAppear {
            if libraryManager.files.isEmpty {
                libraryManager.scan(folder: appState.outputFolder)
            }
        }
    }

    // MARK: - File List

    private var fileList: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tapes…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if libraryManager.isScanning && libraryManager.files.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No .dv files found in output folder." : "No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(filteredFiles, selection: $libraryManager.selectedFile) { file in
                    fileRow(file)
                        .tag(file as DVFile?)
                }
                .listStyle(.plain)
            }
        }
    }

    private func fileRow(_ file: DVFile) -> some View {
        HStack(spacing: 10) {
            // Thumbnail
            Group {
                if let thumbURL = file.thumbnailURL,
                   let img = NSImage(contentsOf: thumbURL) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(Image(systemName: "film").foregroundStyle(.tertiary))
                }
            }
            .frame(width: 56, height: 40)
            .cornerRadius(4)
            .clipped()

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(file.tapeLabel.isEmpty ? file.name : file.tapeLabel)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(file.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    healthBadge(file.health)
                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let file = libraryManager.selectedFile {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fileDetailHeader(file)
                    analysisSection(file)
                    playbackSection(file)
                    exportSection(file)
                }
                .padding(24)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "film.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Select a tape to view details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileDetailHeader(_ file: DVFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.tapeLabel.isEmpty ? file.name : file.tapeLabel)
                        .font(.title2.bold())
                    Text(file.name)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                healthBadge(file.health)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }

            HStack(spacing: 20) {
                labelValue("Size", file.formattedSize)
                labelValue("Duration", file.formattedDuration)
                labelValue("Captured", formatDate(file.captureDate))
                if !file.operatorName.isEmpty {
                    labelValue("Operator", file.operatorName)
                }
            }
        }
    }

    private func analysisSection(_ file: DVFile) -> some View {
        GroupBox("dvrescue Analysis") {
            if file.isAnalyzing {
                HStack { ProgressView().controlSize(.small); Text("Analyzing…").foregroundStyle(.secondary) }
                    .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        analysisCell("Total Frames", "\(file.analysis.totalFrames)", .primary)
                        analysisCell("Error Frames", "\(file.analysis.errorFrames)",
                                     file.analysis.errorFrames > 0 ? .red : .green)
                        analysisCell("Audio Errors", "\(file.analysis.audioErrors)",
                                     file.analysis.audioErrors > 0 ? .yellow : .green)
                        analysisCell("TC Breaks", "\(file.analysis.timecodeBreaks)",
                                     file.analysis.timecodeBreaks > 0 ? .orange : .green)
                    }

                    if !file.analysis.recordingDates.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recording Dates on Tape")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(file.analysis.recordingDates.joined(separator: " · "))
                                .font(.callout)
                        }
                    }

                    Button {
                        reportContent = libraryManager.tapeConditionReport(for: file)
                        showReportSheet = true
                    } label: {
                        Label("Export Tape Condition Report…", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(content: reportContent)
        }
    }

    private func playbackSection(_ file: DVFile) -> some View {
        GroupBox("Playback") {
            VStack(alignment: .leading, spacing: 10) {
                if let proxyURL = file.proxyURL {
                    VideoPlayer(player: AVPlayer(url: proxyURL))
                        .frame(height: 240)
                        .cornerRadius(6)
                    Text("Preview proxy (H.264 640px)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if file.isGeneratingProxy {
                    HStack { ProgressView().controlSize(.small); Text("Generating preview…").foregroundStyle(.secondary) }
                        .frame(height: 80)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "play.slash").foregroundStyle(.secondary)
                        Text("No preview proxy yet.")
                            .foregroundStyle(.secondary)
                        Button("Open in QuickTime") {
                            NSWorkspace.shared.open(file.url)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(height: 60)
                }
            }
            .padding(8)
        }
    }

    private func exportSection(_ file: DVFile) -> some View {
        GroupBox("Export") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    .frame(width: 200)

                    Button("Export…") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = exportFormat == .h264 ? [.mpeg4Movie] : [.quickTimeMovie]
                        panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + ".\(exportFormat.ext)"
                        if panel.runModal() == .OK, let dest = panel.url {
                            libraryManager.export(file: file, format: exportFormat, to: dest)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Helpers

    private func healthBadge(_ health: TapeHealth) -> some View {
        let color: Color = {
            switch health {
            case .good: return .green
            case .warning: return .yellow
            case .poor: return .red
            default: return .gray
            }
        }()
        return Text(health.label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func analysisCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

// MARK: - Report Sheet

struct ReportSheet: View {
    @Environment(\.dismiss) var dismiss
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tape Condition Report").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }

            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.bordered)

                Button {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.plainText]
                    panel.nameFieldStringValue = "tape_condition_report.txt"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? content.write(to: url, atomically: true, encoding: .utf8)
                    }
                } label: { Label("Save as Text…", systemImage: "arrow.down.doc") }
                    .buttonStyle(.bordered)

                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600, height: 500)
    }
}
