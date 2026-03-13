import SwiftUI

struct WindowPickerView: View {
    @EnvironmentObject var windowManager: WindowManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredWindows: [TrackedWindow] {
        let untracked = windowManager.availableWindows.filter { !windowManager.isTracked($0.id) }
        if searchText.isEmpty { return untracked }
        return untracked.filter {
            $0.ownerName.localizedCaseInsensitiveContains(searchText) ||
            $0.windowTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Group windows by app name
    private var groupedWindows: [(String, [TrackedWindow])] {
        let grouped = Dictionary(grouping: filteredWindows) { $0.ownerName }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher une application...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()

            if !windowManager.hasScreenRecordingPermission {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permission \"Enregistrement d'écran\" requise")
                            .font(.callout)
                            .fontWeight(.medium)
                        Text("Sans cette permission, les noms de fenêtres ne sont pas visibles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ouvrir les réglages") {
                        windowManager.openScreenRecordingSettings()
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            if !windowManager.canTrackMore {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Limite de \(windowManager.maxTrackedWindows) fenêtres atteinte")
                        .font(.callout)
                }
                .padding(8)
            }

            Divider()

            // Window list
            List {
                if groupedWindows.isEmpty {
                    Text("Aucune fenêtre disponible")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedWindows, id: \.0) { appName, windows in
                        Section(appName) {
                            ForEach(windows) { window in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(window.windowTitle.isEmpty ? appName : window.windowTitle)
                                            .font(.body)
                                        Text("PID: \(window.pid)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    Button("Ajouter") {
                                        windowManager.trackWindow(window.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(!windowManager.canTrackMore)
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            windowManager.refreshWindows()
        }
    }
}
