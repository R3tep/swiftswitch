import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var notifService: NotificationWatcherService
    @EnvironmentObject var pixelWatcher: PixelWatcherService
    @Binding var selection: LogSelection?
    @Binding var showingPicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Fenêtres suivies") {
                    if windowManager.trackedWindows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aucune fenêtre suivie")
                                .foregroundStyle(.secondary)
                            Text("Cliquez sur \"Ajouter\" pour sélectionner des fenêtres")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                    }

                    ForEach(Array(windowManager.trackedWindows.enumerated()), id: \.element.id) { index, window in
                        WindowRow(window: window, index: index + 1)
                            .tag(LogSelection.window(window.id))
                            .contextMenu {
                                Button("Retirer") {
                                    if case .window(let id) = selection, id == window.id {
                                        selection = nil
                                    }
                                    windowManager.untrackWindow(window.id)
                                }
                            }
                    }
                    .onMove { source, destination in
                        windowManager.moveWindow(from: source, to: destination)
                    }
                }

                Section("Logs") {
                    Label("Toutes les notifications", systemImage: "bell")
                        .tag(LogSelection.globalNotifications)
                }
            }
            .listStyle(.sidebar)

            Divider()

            Toggle("Auto-focus", isOn: $notifService.autoFocusOnNotification)
                .toggleStyle(.switch)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Toggle("Detect dialog", isOn: $pixelWatcher.dialogDetectionEnabled)
                .toggleStyle(.switch)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()

            HStack {
                Button(action: { showingPicker = true }) {
                    Label("Ajouter", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!windowManager.canTrackMore)

                Spacer()

                Text("Tab = suivante")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: { pixelWatcher.saveDebugCapture() }) {
                    Image(systemName: "camera")
                }
                .buttonStyle(.borderless)
                .help("Debug: sauvegarder capture")

                Button(action: { windowManager.refreshWindows() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rafraîchir")
            }
            .padding(8)
        }
        .frame(minWidth: 200)
    }
}

struct WindowRow: View {
    let window: TrackedWindow
    let index: Int
    @EnvironmentObject var windowManager: WindowManager
    @State private var isEditing = false
    @State private var editLabel = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Label", text: $editLabel, onCommit: {
                        windowManager.setLabel(for: window.id, label: editLabel)
                        isEditing = false
                    })
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text(window.label)
                        .font(.headline)
                        .onTapGesture(count: 2) {
                            editLabel = window.label
                            isEditing = true
                        }
                }

                HStack {
                    Text(window.ownerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !window.windowTitle.isEmpty {
                        Text("— \(window.windowTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
