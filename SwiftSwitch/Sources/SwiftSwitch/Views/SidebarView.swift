import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var windowManager: WindowManager
    @Binding var selectedWindowID: CGWindowID?
    @Binding var showingPicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedWindowID) {
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
                        .tag(window.id)
                        .contextMenu {
                            Button("Retirer") {
                                if selectedWindowID == window.id {
                                    selectedWindowID = nil
                                }
                                windowManager.untrackWindow(window.id)
                            }
                        }
                }
                .onMove { source, destination in
                    windowManager.moveWindow(from: source, to: destination)
                }
            }
            .listStyle(.sidebar)

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
