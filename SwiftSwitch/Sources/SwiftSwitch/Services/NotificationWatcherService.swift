import Foundation
import AppKit
import Combine

/// C-level callback for AXObserver — bridges into NotificationWatcherService
private func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notificationName: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let service = Unmanaged<NotificationWatcherService>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    service.handleAXNotification(element: element, notificationName: notificationName as String, pid: pid)
}

/// Monitors macOS distributed notifications and NSWorkspace notifications
/// to detect activity from tracked windows and auto-focus them.
final class NotificationWatcherService: ObservableObject {
    @Published var logs: [pid_t: [LogEntry]] = [:]
    @Published var autoFocusOnNotification = true

    /// Also store a "global" log (pid 0) for unmatched notifications
    private let globalPID: pid_t = 0

    private var trackedWindows: [TrackedWindow] = []
    private let maxEntriesPerPID = 5000
    private weak var windowManager: WindowManager?

    /// Cooldown to avoid rapid-fire switching
    private var lastSwitchTime: Date = .distantPast
    private let switchCooldown: TimeInterval = 2.0

    /// Observers we need to clean up
    private var distributedObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    /// AXObserver per PID
    private var axObservers: [pid_t: AXObserver] = [:]

    /// Log stream process for UNUserNotificationServer
    private var notificationProcess: Process?
    private var notificationPipe: Pipe?

    /// Reference to pixel watcher for combat detection
    weak var pixelWatcher: PixelWatcherService?

    /// Debounce for "Added" notifications (multiple can fire for one turn)
    private var pendingFocusWork: DispatchWorkItem?

    /// Round-robin index into trackedWindows
    private var currentFocusIndex: Int = -1

    func setWindowManager(_ manager: WindowManager) {
        self.windowManager = manager
    }

    func startWatching(for windows: [TrackedWindow]) {
        let oldPIDs = Set(trackedWindows.map(\.pid))
        let newPIDs = Set(windows.map(\.pid))
        trackedWindows = windows

        for w in windows {
            logs[w.pid] = logs[w.pid] ?? []
        }
        logs[globalPID] = logs[globalPID] ?? []

        guard oldPIDs != newPIDs else { return }
        stopAll()
        guard !windows.isEmpty else { return }

        startDistributedNotificationListener()
        startWorkspaceNotificationListener()
        startAXObservers(for: windows)
        startNotificationLogStream()

        appendEntry(LogEntry(
            timestamp: Date(),
            message: "Notification watching started (\(windows.count) windows)",
            pid: windows.first?.pid ?? globalPID,
            source: .info
        ), for: windows.first?.pid ?? globalPID)
    }

    func stopAll() {
        if let obs = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            distributedObserver = nil
        }
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        stopAXObservers()
        notificationProcess?.terminate()
        notificationProcess = nil
    }

    func clearLogs(for pid: pid_t) {
        logs[pid] = []
    }

    // MARK: - Distributed Notifications (inter-app)

    private func startDistributedNotificationListener() {
        // Listen to ALL distributed notifications
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: nil,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleDistributedNotification(notification)
        }
    }

    private func handleDistributedNotification(_ notification: Notification) {
        let name = notification.name.rawValue
        let object = notification.object as? String ?? "nil"
        let userInfo = notification.userInfo?.description ?? ""

        let message = "[\(name)] obj=\(object)" + (userInfo.isEmpty ? "" : " info=\(userInfo)")

        // Try to match to a tracked window by app name
        if let matched = matchNotificationToWindow(name: name, object: object, userInfo: notification.userInfo) {
            appendEntry(LogEntry(
                timestamp: Date(),
                message: message,
                pid: matched.pid,
                source: .notif
            ), for: matched.pid)

            // Auto-focus if enabled
            if autoFocusOnNotification {
                tryAutoFocus(matched)
            }
        } else {
            // Log to global
            appendEntry(LogEntry(
                timestamp: Date(),
                message: message,
                pid: globalPID,
                source: .notif
            ), for: globalPID)
        }
    }

    // MARK: - Workspace Notifications

    private func startWorkspaceNotificationListener() {
        let nc = NSWorkspace.shared.notificationCenter

        let notifNames: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]

        for notifName in notifNames {
            let obs = nc.addObserver(forName: notifName, object: nil, queue: .main) { [weak self] notification in
                self?.handleWorkspaceNotification(notification)
            }
            workspaceObservers.append(obs)
        }
    }

    private func handleWorkspaceNotification(_ notification: Notification) {
        let name = notification.name.rawValue

        var appName = ""
        var appPID: pid_t?

        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            appName = app.localizedName ?? app.bundleIdentifier ?? "unknown"
            appPID = app.processIdentifier
        }

        let message = "WS: [\(name)] app=\(appName)" + (appPID != nil ? " pid=\(appPID!)" : "")

        // Match by PID
        if let pid = appPID, let matched = trackedWindows.first(where: { $0.pid == pid }) {
            appendEntry(LogEntry(
                timestamp: Date(),
                message: message,
                pid: matched.pid,
                source: .info
            ), for: matched.pid)
        } else {
            appendEntry(LogEntry(
                timestamp: Date(),
                message: message,
                pid: globalPID,
                source: .info
            ), for: globalPID)
        }
    }

    // MARK: - UNUserNotification log stream (turn detection trigger)

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
            appendEntry(LogEntry(
                timestamp: Date(),
                message: "Log stream started (UNUserNotificationServer)",
                pid: globalPID,
                source: .info
            ), for: globalPID)
        } catch {
            appendEntry(LogEntry(
                timestamp: Date(),
                message: "Failed to start log stream: \(error)",
                pid: globalPID,
                source: .info
            ), for: globalPID)
        }
    }

    private func handleNotificationLog(_ line: String) {
        var message = line
        if let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            message = json["eventMessage"] as? String ?? line
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let entry = LogEntry(
                timestamp: Date(),
                message: "NOTIF-LOG: \(message)",
                pid: self.globalPID,
                source: .notif
            )
            self.appendEntry(entry, for: self.globalPID)

            // "Added" = a turn notification was posted → focus next window (debounced)
            if message.hasPrefix("Added") {
                self.pendingFocusWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.focusNextWindow()
                }
                self.pendingFocusWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)

                // Also scan for Oui/Non dialog 100ms later (one-shot)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                    self?.pixelWatcher?.scanForOuiNonDialog()
                }
            }
        }
    }

    // MARK: - AXObserver (Accessibility per-window events)

    /// All AX notification names we want to observe
    private static let axNotifications: [String] = [
        kAXValueChangedNotification,
        kAXTitleChangedNotification,
        kAXFocusedUIElementChangedNotification,
        kAXLayoutChangedNotification,
        kAXWindowCreatedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
        kAXSelectedTextChangedNotification,
        kAXSelectedChildrenChangedNotification,
        kAXSelectedRowsChangedNotification,
        kAXRowExpandedNotification,
        kAXRowCollapsedNotification,
    ]

    private func startAXObservers(for windows: [TrackedWindow]) {
        stopAXObservers()

        // Group windows by PID (one observer per PID)
        let pidSet = Set(windows.map(\.pid))

        for pid in pidSet {
            var observer: AXObserver?
            let err = AXObserverCreate(pid, axCallback, &observer)
            guard err == .success, let obs = observer else {
                appendEntry(LogEntry(
                    timestamp: Date(),
                    message: "AX: Failed to create observer for pid=\(pid) err=\(err.rawValue)",
                    pid: pid,
                    source: .ax
                ), for: pid)
                continue
            }

            let appElement = AXUIElementCreateApplication(pid)

            // Pass self as refcon via Unmanaged
            let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

            for notifName in Self.axNotifications {
                AXObserverAddNotification(obs, appElement, notifName as CFString, refcon)
            }

            // Also observe on each window element specifically
            var windowsRef: AnyObject?
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            if let axWindows = windowsRef as? [AXUIElement] {
                for axWindow in axWindows {
                    for notifName in Self.axNotifications {
                        AXObserverAddNotification(obs, axWindow, notifName as CFString, refcon)
                    }
                }
            }

            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            axObservers[pid] = obs

            appendEntry(LogEntry(
                timestamp: Date(),
                message: "AX: Observer started for pid=\(pid)",
                pid: pid,
                source: .ax
            ), for: pid)
        }
    }

    private func stopAXObservers() {
        for (_, obs) in axObservers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        axObservers.removeAll()
    }

    /// Called from the C callback on the main thread
    fileprivate func handleAXNotification(element: AXUIElement, notificationName: String, pid: pid_t) {
        // Try to get a description of the element
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "?"

        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""

        var valueRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let value = valueRef as? String ?? ""

        var desc = "AX: [\(notificationName)] role=\(role)"
        if !title.isEmpty { desc += " title=\"\(title)\"" }
        if !value.isEmpty { desc += " value=\"\(value.prefix(100))\"" }

        appendEntry(LogEntry(
            timestamp: Date(),
            message: desc,
            pid: pid,
            source: .ax
        ), for: pid)

        // Also log to global
        appendEntry(LogEntry(
            timestamp: Date(),
            message: desc,
            pid: pid,
            source: .ax
        ), for: globalPID)
    }

    // MARK: - Matching & Auto-focus

    /// Try to match a distributed notification to one of our tracked windows
    private func matchNotificationToWindow(name: String, object: String, userInfo: [AnyHashable: Any]?) -> TrackedWindow? {
        // Check if the notification name or object contains a tracked app name
        let nameLower = name.lowercased()
        let objectLower = object.lowercased()

        for window in trackedWindows {
            let appLower = window.ownerName.lowercased()
            if nameLower.contains(appLower) || objectLower.contains(appLower) {
                return window
            }

            // Also check bundle identifier patterns
            let bundlePattern = appLower.replacingOccurrences(of: " ", with: "")
            if nameLower.contains(bundlePattern) || objectLower.contains(bundlePattern) {
                return window
            }
        }

        // Check userInfo for any PID or bundle ID references
        if let info = userInfo {
            for (_, value) in info {
                let valStr = "\(value)".lowercased()
                for window in trackedWindows {
                    if valStr.contains(window.ownerName.lowercased()) {
                        return window
                    }
                }
            }
        }

        return nil
    }

    /// Called when combat ends: reset round-robin and focus first window
    func handleCombatEnd() {
        currentFocusIndex = -1
        guard !trackedWindows.isEmpty else { return }
        let first = trackedWindows[0]
        windowManager?.focusWindow(first)
        appendEntry(LogEntry(
            timestamp: Date(),
            message: "⚔️ FIN COMBAT → \(first.label)",
            pid: first.pid,
            source: .spike
        ), for: globalPID)
    }

    /// Round-robin: focus the next tracked window (only if in combat)
    private func focusNextWindow() {
        guard pixelWatcher?.isInCombat == true else { return }
        guard autoFocusOnNotification else { return }
        guard !trackedWindows.isEmpty else { return }

        currentFocusIndex = (currentFocusIndex + 1) % trackedWindows.count
        let window = trackedWindows[currentFocusIndex]
        windowManager?.focusWindow(window)

        appendEntry(LogEntry(
            timestamp: Date(),
            message: "★ TOUR → \(window.label) [\(currentFocusIndex + 1)/\(trackedWindows.count)]",
            pid: window.pid,
            source: .spike
        ), for: globalPID)
    }

    private func tryAutoFocus(_ window: TrackedWindow) {
        let now = Date()
        guard now.timeIntervalSince(lastSwitchTime) > switchCooldown else { return }

        lastSwitchTime = now
        windowManager?.focusWindow(window)

        appendEntry(LogEntry(
            timestamp: Date(),
            message: "★ AUTO-FOCUS → \(window.label)",
            pid: window.pid,
            source: .spike
        ), for: window.pid)
    }

    // MARK: - Log management

    /// Public entry point for external services (e.g. PixelWatcherService) to append logs
    func appendLogEntry(_ entry: LogEntry, for pid: pid_t) {
        appendEntry(entry, for: pid)
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
