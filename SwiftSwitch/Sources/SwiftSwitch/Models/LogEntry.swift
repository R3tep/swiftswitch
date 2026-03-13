import Foundation

enum LogSource: String {
    case notification = "NOTIF"
    case distributed = "DIST"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let pid: pid_t
    let source: LogSource
}
