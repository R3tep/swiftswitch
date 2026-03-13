import SwiftUI

struct ContentView: View {
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var notifService: NotificationWatcherService
    @State private var selectedWindowID: CGWindowID?
    @State private var showingPicker = false

    private var selectedWindow: TrackedWindow? {
        windowManager.trackedWindows.first { $0.id == selectedWindowID }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedWindowID: $selectedWindowID, showingPicker: $showingPicker)
        } detail: {
            LogView(window: selectedWindow)
        }
        .navigationTitle("SwiftSwitch")
        .sheet(isPresented: $showingPicker) {
            WindowPickerView()
        }
        .onChange(of: windowManager.trackedWindows) { tracked in
            notifService.startWatching(for: tracked)
        }
    }
}
