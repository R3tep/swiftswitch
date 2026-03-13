import SwiftUI
import AppKit

@main
struct SwiftSwitchApp: App {
    @StateObject private var windowManager = WindowManager()
    @StateObject private var switchService = WindowSwitchService()
    @StateObject private var notifService = NotificationWatcherService()
    @StateObject private var pixelWatcher = PixelWatcherService()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(windowManager)
                .environmentObject(notifService)
                .environmentObject(pixelWatcher)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    switchService.setWindowManager(windowManager)
                    notifService.setWindowManager(windowManager)
                    pixelWatcher.configure(notifService: notifService, windowManager: windowManager)
                    notifService.pixelWatcher = pixelWatcher
                    pixelWatcher.onCombatEnd = { [weak notifService] in
                        notifService?.handleCombatEnd()
                    }
                    switchService.start()
                    windowManager.refreshWindows()
                    notifService.startWatching(for: windowManager.trackedWindows)
                    pixelWatcher.updateWindows(windowManager.trackedWindows)
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
