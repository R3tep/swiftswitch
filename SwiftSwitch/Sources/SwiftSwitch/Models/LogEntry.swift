import Foundation

enum LogSource: String {
    case spike = "SPIKE"
    case info = "INFO"
    case notif = "NOTIF"
    case ax = "AX"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let pid: pid_t
    let source: LogSource
}
