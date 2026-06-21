import SwiftUI
import UserNotifications

@main
struct DVRescue_StudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var captureManager = CaptureManager.shared
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var toolManager = ToolManager.shared
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(captureManager)
                .environmentObject(libraryManager)
                .environmentObject(toolManager)
                .environmentObject(menuBarManager)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    Task { await toolManager.checkAllTools() }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    // Sparkle: SUUpdater.shared()?.checkForUpdates(nil)
                }
                .keyboardShortcut("U", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(toolManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        CaptureManager.shared.stopCapture()
    }
}
