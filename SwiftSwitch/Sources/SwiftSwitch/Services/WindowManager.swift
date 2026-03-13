import Foundation
import CoreGraphics
import Combine
import AppKit

// Private API to get CGWindowID from AXUIElement
// Used by all major macOS window managers (yabai, Amethyst, etc.)
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

final class WindowManager: ObservableObject {
    /// All system windows available to pick from
    @Published var availableWindows: [TrackedWindow] = []
    /// Windows the user has chosen to track, in user-defined order
    @Published var trackedWindows: [TrackedWindow] = []
    /// Whether Screen Recording permission is granted
    @Published var hasScreenRecordingPermission = false
    @Published var labels: [CGWindowID: String] = [:] {
        didSet { saveLabels() }
    }

    /// Ordered list of tracked window IDs (user-defined order)
    private var orderedTrackedIDs: [CGWindowID] = [] {
        didSet { saveTrackedIDs() }
    }
    private var timer: AnyCancellable?
    private let labelsKey = "SwiftSwitch.windowLabels"
    private let trackedIDsKey = "SwiftSwitch.trackedIDs"

    init() {
        loadLabels()
        loadTrackedIDs()
        checkScreenRecordingPermission()
        refreshWindows()
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkScreenRecordingPermission()
                self?.refreshWindows()
            }
    }

    /// Check if we can read window names (indicates Screen Recording permission)
    func checkScreenRecordingPermission() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            hasScreenRecordingPermission = false
            return
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        hasScreenRecordingPermission = list.contains { entry in
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let name = entry[kCGWindowName as String] as? String ?? ""
            return pid != myPID && !name.isEmpty
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshWindows() {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        var all: [TrackedWindow] = []

        for entry in windowList {
            guard let ownerName = entry[kCGWindowOwnerName as String] as? String,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            let title = entry[kCGWindowName as String] as? String ?? ""

            let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Skip tiny windows (menus, tooltips, status bar items, etc.)
            if bounds.width < 100 || bounds.height < 100 { continue }

            let displayName = title.isEmpty ? ownerName : "\(ownerName) - \(title)"
            let label = labels[windowID] ?? displayName

            all.append(TrackedWindow(
                id: windowID,
                pid: pid,
                windowTitle: title,
                ownerName: ownerName,
                label: label,
                bounds: bounds
            ))
        }

        availableWindows = all

        // Build trackedWindows in the user-defined order
        let trackedSet = Set(orderedTrackedIDs)
        let allByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        trackedWindows = orderedTrackedIDs.compactMap { id in
            allByID[id]
        }
        // Only remove tracked IDs if the owning process is no longer running (window truly closed)
        // Don't remove just because the window is off-screen (different desktop/space)
        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        orderedTrackedIDs = orderedTrackedIDs.filter { id in
            // Keep if window is still visible
            if all.contains(where: { $0.id == id }) { return true }
            // Keep if we don't know the PID (not tracked) — shouldn't happen but safe
            guard trackedSet.contains(id) else { return true }
            // Remove only if the process that owned it is gone
            if let lastKnown = trackedWindows.first(where: { $0.id == id }) {
                return runningPIDs.contains(lastKnown.pid)
            }
            return false
        }
    }

    let maxTrackedWindows = 8

    func trackWindow(_ windowID: CGWindowID) {
        guard orderedTrackedIDs.count < maxTrackedWindows else { return }
        if !orderedTrackedIDs.contains(windowID) {
            orderedTrackedIDs.append(windowID)
        }
        refreshWindows()
    }

    var canTrackMore: Bool {
        orderedTrackedIDs.count < maxTrackedWindows
    }

    func untrackWindow(_ windowID: CGWindowID) {
        orderedTrackedIDs.removeAll { $0 == windowID }
        refreshWindows()
    }

    func isTracked(_ windowID: CGWindowID) -> Bool {
        orderedTrackedIDs.contains(windowID)
    }

    func moveWindow(from source: IndexSet, to destination: Int) {
        orderedTrackedIDs.move(fromOffsets: source, toOffset: destination)
        refreshWindows()
    }

    func setLabel(for windowID: CGWindowID, label: String) {
        labels[windowID] = label
        if let idx = trackedWindows.firstIndex(where: { $0.id == windowID }) {
            trackedWindows[idx].label = label
        }
    }

    // MARK: - Window switching

    /// Get the next tracked window after the given one (cycles)
    func nextWindow(after windowID: CGWindowID) -> TrackedWindow? {
        guard trackedWindows.count > 1 else { return nil }
        guard let currentIdx = trackedWindows.firstIndex(where: { $0.id == windowID }) else {
            return trackedWindows.first
        }
        let nextIdx = (currentIdx + 1) % trackedWindows.count
        return trackedWindows[nextIdx]
    }

    /// Bring a window to the front using its CGWindowID
    func focusWindow(_ window: TrackedWindow) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsRef: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var cgWindowID: CGWindowID = 0
            let result = _AXUIElementGetWindow(axWindow, &cgWindowID)
            if result == .success && cgWindowID == window.id {
                // 1. Set this window as the focused window of the application
                AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, axWindow)
                // 2. Set it as the main window
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFBoolean)
                // 3. Raise it in the window stack
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                break
            }
        }

        // 4. Make the app frontmost via AX (more reliable than NSRunningApplication)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, true as CFBoolean)
    }

    // MARK: - Persistence

    private func saveLabels() {
        let stringKeyed = labels.reduce(into: [String: String]()) { result, pair in
            result["\(pair.key)"] = pair.value
        }
        UserDefaults.standard.set(stringKeyed, forKey: labelsKey)
    }

    private func loadLabels() {
        guard let saved = UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String] else { return }
        labels = saved.reduce(into: [CGWindowID: String]()) { result, pair in
            if let key = CGWindowID(pair.key) {
                result[key] = pair.value
            }
        }
    }

    private func saveTrackedIDs() {
        let array = orderedTrackedIDs.map { "\($0)" }
        UserDefaults.standard.set(array, forKey: trackedIDsKey)
    }

    private func loadTrackedIDs() {
        guard let saved = UserDefaults.standard.stringArray(forKey: trackedIDsKey) else { return }
        orderedTrackedIDs = saved.compactMap { CGWindowID($0) }
    }
}
