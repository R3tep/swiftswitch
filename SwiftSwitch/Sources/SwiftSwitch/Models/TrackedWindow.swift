import Foundation
import CoreGraphics

struct TrackedWindow: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let windowTitle: String
    let ownerName: String
    var label: String
    let bounds: CGRect

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrackedWindow, rhs: TrackedWindow) -> Bool {
        lhs.id == rhs.id
    }
}
