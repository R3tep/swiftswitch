import SwiftUI

/// Shows all notifications (both matched and unmatched) in a single log view
struct GlobalLogView: View {
    @EnvironmentObject var notifService: NotificationWatcherService
    @State private var filterText = ""
    @State private var autoScroll = true

    private var entries: [LogEntry] {
        // Merge all logs from all PIDs, sorted by timestamp
        let merged: [LogEntry] = notifService.logs.values.flatMap { $0 }
        let filtered = merged.filter { entry in
            entry.source == .spike || (entry.source == .notif && entry.message.contains("Added"))
        }
        let sorted = filtered.sorted { $0.timestamp < $1.timestamp }
        if filterText.isEmpty { return sorted }
        return sorted.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filtrer...", text: $filterText)
                    .textFieldStyle(.roundedBorder)

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)

                Button("Effacer tout") {
                    for pid in notifService.logs.keys {
                        notifService.clearLogs(for: pid)
                    }
                }
            }
            .padding(8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(entry.source.rawValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(sourceColor(entry.source))
                                    .frame(width: 42)
                                if entry.pid != 0 {
                                    Text("[\(entry.pid)]")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.blue)
                                        .frame(width: 60)
                                }
                                Text(entry.message)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: entries.count) { _ in
                    if autoScroll, let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 400)
    }

    private func sourceColor(_ source: LogSource) -> Color {
        switch source {
        case .spike: return .green
        case .notif: return .orange
        case .ax: return .purple
        case .info: return .secondary
        }
    }
}
