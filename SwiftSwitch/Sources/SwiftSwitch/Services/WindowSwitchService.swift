import Foundation
import AppKit
import Combine

/// Listens for Tab key press on tracked windows and switches to the next one
final class WindowSwitchService: ObservableObject {
    private var eventMonitor: Any?
    private weak var windowManager: WindowManager?

    func setWindowManager(_ manager: WindowManager) {
        self.windowManager = manager
    }

    func start() {
        guard eventMonitor == nil else { return }

        // Global monitor: captures key events even when our app is NOT focused
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Tab key = keyCode 48
        guard event.keyCode == 48 else { return }
        guard let manager = windowManager else { return }
        guard manager.trackedWindows.count > 1 else { return }

        // Find which tracked app is currently focused
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let frontPID = frontApp.processIdentifier

        // Find the current tracked window by PID
        // If multiple windows share the same PID, we use the first match
        // and cycle through all tracked windows regardless
        let trackedPIDs = Set(manager.trackedWindows.map(\.pid))
        guard trackedPIDs.contains(frontPID) else { return }

        // Find current window - refresh bounds first to get accurate positions
        manager.refreshWindows()

        guard let currentWindow = manager.trackedWindows.first(where: { $0.pid == frontPID }) else {
            return
        }

        // Switch to the next window in the ordered list
        if let nextWindow = manager.nextWindow(after: currentWindow.id) {
            manager.focusWindow(nextWindow)
        }
    }

    deinit {
        stop()
    }
}
