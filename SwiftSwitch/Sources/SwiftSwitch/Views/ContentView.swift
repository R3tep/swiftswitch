import SwiftUI

enum LogSelection: Hashable {
    case window(CGWindowID)
    case globalNotifications
}

struct ContentView: View {
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var notifService: NotificationWatcherService
    @EnvironmentObject var pixelWatcher: PixelWatcherService
    @State private var selection: LogSelection?
    @State private var showingPicker = false

    private var selectedWindow: TrackedWindow? {
        if case .window(let id) = selection {
            return windowManager.trackedWindows.first { $0.id == id }
        }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, showingPicker: $showingPicker)
        } detail: {
            switch selection {
            case .window:
                LogView(window: selectedWindow)
            case .globalNotifications:
                GlobalLogView()
            case nil:
                Text("Sélectionnez une fenêtre ou le log global")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SwiftSwitch")
        .sheet(isPresented: $showingPicker) {
            WindowPickerView()
        }
        .onChange(of: windowManager.trackedWindows) { tracked in
            notifService.startWatching(for: tracked)
            pixelWatcher.updateWindows(tracked)
        }
    }
}
