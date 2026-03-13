import SwiftUI

struct LogView: View {
    let window: TrackedWindow?
    @EnvironmentObject var notifService: NotificationWatcherService
    @State private var filterText = ""
    @State private var autoScroll = true

    private var entries: [LogEntry] {
        guard let window = window else { return [] }
        let all = (notifService.logs[window.pid] ?? [])
            .filter { $0.source == .spike || ($0.source == .notif && $0.message.contains("Added")) }
        if filterText.isEmpty { return all }
        return all.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let window = window {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filtrer...", text: $filterText)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.switch)

                    Button("Effacer") {
                        notifService.clearLogs(for: window.pid)
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
            } else {
                VStack {
                    Spacer()
                    Text("Sélectionnez une fenêtre pour voir les notifications")
                        .foregroundStyle(.secondary)
                    Spacer()
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
