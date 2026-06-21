import SwiftUI

enum NavItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case install = "Install"
    case capture = "Capture"
    case library = "Library"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .install: return "arrow.down.circle"
        case .capture: return "record.circle"
        case .library: return "folder"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: NavItem? = .home

    var body: some View {
        NavigationSplitView {
            List(NavItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection ?? .home {
                case .home:    HomeView()
                case .install: InstallView()
                case .capture: CaptureView()
                case .library: LibraryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.pendingNavigation) { _, nav in
            if let nav { selection = nav; appState.pendingNavigation = nil }
        }
    }
}
