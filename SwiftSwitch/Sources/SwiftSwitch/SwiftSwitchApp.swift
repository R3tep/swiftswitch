import SwiftUI
import AppKit

@main
struct SwiftSwitchApp: App {
    @StateObject private var windowManager = WindowManager()
    @StateObject private var switchService = WindowSwitchService()
    @StateObject private var notifService = NotificationWatcherService()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(windowManager)
                .environmentObject(notifService)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    switchService.setWindowManager(windowManager)
                    notifService.setWindowManager(windowManager)
                    switchService.start()
                    windowManager.refreshWindows()
                    notifService.startWatching(for: windowManager.trackedWindows)
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
