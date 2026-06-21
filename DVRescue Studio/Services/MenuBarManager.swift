import AppKit

class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?

    func startShowing(session: CaptureSession) {
        DispatchQueue.main.async {
            if self.statusItem == nil {
                self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                self.statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            }
            self.updateTimer?.invalidate()
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak session] _ in
                guard let session else { self?.stopShowing(); return }
                let elapsed = session.formattedElapsed
                let frames  = session.frameCount
                self?.statusItem?.button?.title = "⏺ \(elapsed)  \(frames)f"
            }
        }
    }

    func stopShowing() {
        DispatchQueue.main.async {
            self.updateTimer?.invalidate(); self.updateTimer = nil
            if let item = self.statusItem {
                NSStatusBar.system.removeStatusItem(item)
                self.statusItem = nil
            }
        }
    }
}
