import Foundation
import AppKit

/// Watches for notifications from tracked processes via multiple channels
final class NotificationWatcherService: ObservableObject {
    @Published var logs: [pid_t: [LogEntry]] = [:]
    @Published var autoFocusOnNotification = true

    private var trackedPIDs: Set<pid_t> = []
    private var trackedWindows: [TrackedWindow] = []
    private var notificationProcess: Process?
    private var notificationPipe: Pipe?
    private let maxEntriesPerPID = 5000
    private weak var windowManager: WindowManager?

    func setWindowManager(_ manager: WindowManager) {
        self.windowManager = manager
    }

    func startWatching(for windows: [TrackedWindow]) {
        let newPIDs = Set(windows.map(\.pid))
        trackedWindows = windows
        guard newPIDs != trackedPIDs else { return }
        trackedPIDs = newPIDs

        // Initialize logs for new PIDs
        for pid in newPIDs where logs[pid] == nil {
            logs[pid] = []
        }

        startDistributedNotificationListener()
        startNotificationLogStream()
    }

    func stopAll() {
        DistributedNotificationCenter.default().removeObserver(self)
        notificationProcess?.terminate()
        notificationProcess = nil
    }

    func clearLogs(for pid: pid_t) {
        logs[pid] = []
    }

    // MARK: - Distributed Notifications

    private func startDistributedNotificationListener() {
        let center = DistributedNotificationCenter.default()
        center.removeObserver(self)

        center.addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: nil,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleDistributedNotification(_ notification: Notification) {
        let name = notification.name.rawValue
        let object = notification.object as? String ?? ""
        let userInfo = notification.userInfo ?? [:]

        let isRelevant = object.lowercased().contains("dofus") ||
                         name.lowercased().contains("dofus") ||
                         name.lowercased().contains("ankama") ||
                         object.lowercased().contains("ankama")

        let isSystem = name.hasPrefix("com.apple.") ||
                       name.hasPrefix("NSWorkspace") ||
                       name.hasPrefix("AppleSystem")

        guard isRelevant || !isSystem else { return }

        var message = "[\(name)]"
        if !object.isEmpty {
            message += " from: \(object)"
        }
        if !userInfo.isEmpty {
            let info = userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            message += " {\(info)}"
        }

        let entry = LogEntry(
            timestamp: Date(),
            message: message,
            pid: 0,
            source: .distributed
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for pid in self.trackedPIDs {
                self.appendEntry(entry, for: pid)
            }
            self.autoFocusIfNeeded()
        }
    }

    // MARK: - UserNotification monitoring via log stream

    private func startNotificationLogStream() {
        notificationProcess?.terminate()

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--predicate",
            "subsystem == \"com.apple.UNUserNotificationServer\" OR process == \"usernoted\"",
            "--style", "ndjson",
            "--level", "info"
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let fileHandle = pipe.fileHandleForReading
        var buffer = Data()

        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }

                let lower = line.lowercased()
                guard lower.contains("dofus") || lower.contains("ankama") else { continue }

                self?.handleNotificationLog(line)
            }
        }

        process.terminationHandler = { [weak self] _ in
            fileHandle.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.notificationProcess = nil
            }
        }

        do {
            try process.run()
            notificationProcess = process
            notificationPipe = pipe
        } catch {
            print("Failed to start notification log stream: \(error)")
        }
    }

    private func handleNotificationLog(_ line: String) {
        var message = line
        if let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            message = json["eventMessage"] as? String ?? line
        }

        let entry = LogEntry(
            timestamp: Date(),
            message: message,
            pid: 0,
            source: .notification
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for pid in self.trackedPIDs {
                self.appendEntry(entry, for: pid)
            }
            self.autoFocusIfNeeded()
        }
    }

    // MARK: - Auto-focus

    /// When a notification is received, switch to the next tracked window
    private func autoFocusIfNeeded() {
        guard autoFocusOnNotification else { return }
        guard let manager = windowManager else { return }
        guard trackedWindows.count > 1 else { return }

        // Find the currently frontmost tracked window by checking the window order
        // The topmost window in CGWindowList that matches a tracked ID is the current one
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        let trackedIDs = Set(trackedWindows.map(\.id))

        // Find the frontmost tracked window (first in the z-order list)
        var currentWindowID: CGWindowID?
        for entry in windowList {
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            if trackedIDs.contains(windowID) {
                currentWindowID = windowID
                break
            }
        }

        guard let currentID = currentWindowID else { return }

        // Focus the next window in our ordered list
        if let next = manager.nextWindow(after: currentID) {
            manager.focusWindow(next)
        }
    }

    private func appendEntry(_ entry: LogEntry, for pid: pid_t) {
        logs[pid, default: []].append(entry)
        if logs[pid]!.count > maxEntriesPerPID {
            logs[pid]!.removeFirst(logs[pid]!.count - maxEntriesPerPID)
        }
    }

    deinit {
        stopAll()
    }
}
