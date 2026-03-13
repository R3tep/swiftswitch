import Foundation
import CoreGraphics
import AppKit
import Combine

/// Monitors tracked windows to detect combat state and dialog popups.
/// Polls every second.
final class PixelWatcherService: ObservableObject {
    @Published var isInCombat = false
    @Published var dialogDetectionEnabled = true
    private var trackedWindows: [TrackedWindow] = []
    private var timer: Timer?
    private weak var notifService: NotificationWatcherService?
    private weak var windowManager: WindowManager?

    /// Called when combat ends (isInCombat transitions true → false)
    var onCombatEnd: (() -> Void)?

    /// Minimum % of orange pixels to consider "in combat"
    private let combatPercentage: Double = 0.40

    /// Tiny region targeting just the flag's orange background (below portrait)
    private struct FlagRegionRatios {
        let xStart: CGFloat = 0.67
        let xEnd: CGFloat = 0.69
        let yStart: CGFloat = 0.95
        let yEnd: CGFloat = 0.97
    }
    private let flagRegion = FlagRegionRatios()

    // MARK: - Dialog Detection (Oui/Non)

    /// Left button region ("Oui")
    private let ouiRegion = (xStart: CGFloat(0.53), xEnd: CGFloat(0.61), yStart: CGFloat(0.43), yEnd: CGFloat(0.48))
    /// Gap between the two buttons — should have NO orange if it's Oui/Non
    private let gapRegion = (xStart: CGFloat(0.62), xEnd: CGFloat(0.65), yStart: CGFloat(0.43), yEnd: CGFloat(0.48))
    /// Right button region ("Non")
    private let nonRegion = (xStart: CGFloat(0.66), xEnd: CGFloat(0.74), yStart: CGFloat(0.43), yEnd: CGFloat(0.48))

    /// Minimum % of orange pixels per button to consider it present
    private let dialogButtonPercentage: Double = 0.03

    func configure(notifService: NotificationWatcherService, windowManager: WindowManager) {
        self.notifService = notifService
        self.windowManager = windowManager
    }

    func updateWindows(_ windows: [TrackedWindow]) {
        trackedWindows = windows
        if windows.isEmpty {
            stopPolling()
            isInCombat = false
        } else {
            startPolling()
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkCombatStatus()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func checkCombatStatus() {
        guard let window = trackedWindows.first else {
            if isInCombat { isInCombat = false }
            return
        }
        let (orangeCount, totalPixels) = countOrangePixels(for: window)
        let percentage = totalPixels > 0 ? Double(orangeCount) / Double(totalPixels) : 0
        let inCombat = percentage >= combatPercentage

        if inCombat != isInCombat {
            let wasInCombat = isInCombat
            isInCombat = inCombat
            log("Combat: \(inCombat ? "EN COMBAT" : "HORS COMBAT") (\(Int(percentage * 100))% orange, \(orangeCount)/\(totalPixels)px)",
                pid: window.pid, source: .spike)
            if wasInCombat && !inCombat {
                onCombatEnd?()
            }
        }
    }

    /// Save a debug screenshot of the flag region for the first tracked window
    func saveDebugCapture() {
        guard let window = trackedWindows.first else { return }
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            window.id,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else { return }

        let imgWidth = image.width
        let imgHeight = image.height

        let regionX = Int(CGFloat(imgWidth) * flagRegion.xStart)
        let regionY = Int(CGFloat(imgHeight) * flagRegion.yStart)
        let regionW = Int(CGFloat(imgWidth) * (flagRegion.xEnd - flagRegion.xStart))
        let regionH = Int(CGFloat(imgHeight) * (flagRegion.yEnd - flagRegion.yStart))

        // Save the cropped region
        if let cropped = image.cropping(to: CGRect(x: regionX, y: regionY, width: regionW, height: regionH)) {
            let nsImage = NSImage(cgImage: cropped, size: NSSize(width: regionW, height: regionH))
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let path = "/tmp/swiftswitch_capture_region.png"
                try? pngData.write(to: URL(fileURLWithPath: path))
                log("DEBUG: Saved flag region to \(path) (\(regionW)x\(regionH) at \(regionX),\(regionY) of \(imgWidth)x\(imgHeight))", pid: window.pid, source: .info)
            }
        }

        // Also save the full window for reference
        let nsImageFull = NSImage(cgImage: image, size: NSSize(width: imgWidth, height: imgHeight))
        if let tiffData = nsImageFull.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let path = "/tmp/swiftswitch_full_window.png"
            try? pngData.write(to: URL(fileURLWithPath: path))
            log("DEBUG: Saved full window to \(path) (\(imgWidth)x\(imgHeight))", pid: window.pid, source: .info)
        }
    }

    // MARK: - Dialog Detection (one-shot, triggered by NotificationWatcherService)

    /// Scan all tracked windows once for a "Oui/Non" dialog (two orange buttons).
    /// If found, focus that window. Called ~500ms after an "Added" notification.
    func scanForOuiNonDialog() {
        guard dialogDetectionEnabled, !isInCombat else { return }

        struct ScanResult {
            let window: TrackedWindow
            let ouiPct: Double
            let nonPct: Double
            let ouiCount: Int
            let ouiTotal: Int
            let nonCount: Int
            let nonTotal: Int
            let hasBothButtons: Bool
        }

        for (idx, window) in trackedWindows.enumerated() {
            guard let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                window.id,
                [.boundsIgnoreFraming, .nominalResolution]
            ) else { continue }

            let imgW = image.width
            let imgH = image.height

            // Temporarily save all windows for calibration
            saveImage(image, to: "/tmp/swiftswitch_dialog_full_\(idx).png")

            let (ouiCount, ouiTotal) = countOrangeInImage(image, region: ouiRegion)
            let ouiPct = ouiTotal > 0 ? Double(ouiCount) / Double(ouiTotal) : 0

            let (gapCount, gapTotal) = countOrangeInImage(image, region: gapRegion)
            let gapPct = gapTotal > 0 ? Double(gapCount) / Double(gapTotal) : 0

            let (nonCount, nonTotal) = countOrangeInImage(image, region: nonRegion)
            let nonPct = nonTotal > 0 ? Double(nonCount) / Double(nonTotal) : 0

            // Two buttons with a gap = Oui/Non. One button (Annuler) has orange in the gap.
            let hasBoth = ouiPct >= dialogButtonPercentage && nonPct >= dialogButtonPercentage && gapPct < 0.10

            log("Dialog scan \(window.label): oui=\(Int(ouiPct * 100))% gap=\(Int(gapPct * 100))% non=\(Int(nonPct * 100))% → \(hasBoth ? "OUI/NON" : "skip")",
                pid: window.pid, source: .spike)

            if hasBoth {
                // Save debug screenshots only when dialog is found
                saveImage(image, to: "/tmp/swiftswitch_dialog_full_\(idx).png")
                let ouiRect = CGRect(
                    x: CGFloat(imgW) * ouiRegion.xStart,
                    y: CGFloat(imgH) * ouiRegion.yStart,
                    width: CGFloat(imgW) * (ouiRegion.xEnd - ouiRegion.xStart),
                    height: CGFloat(imgH) * (ouiRegion.yEnd - ouiRegion.yStart)
                )
                if let cropped = image.cropping(to: ouiRect) {
                    saveImage(cropped, to: "/tmp/swiftswitch_dialog_oui_\(idx).png")
                }
                let nonRect = CGRect(
                    x: CGFloat(imgW) * nonRegion.xStart,
                    y: CGFloat(imgH) * nonRegion.yStart,
                    width: CGFloat(imgW) * (nonRegion.xEnd - nonRegion.xStart),
                    height: CGFloat(imgH) * (nonRegion.yEnd - nonRegion.yStart)
                )
                if let cropped = image.cropping(to: nonRect) {
                    saveImage(cropped, to: "/tmp/swiftswitch_dialog_non_\(idx).png")
                }

                windowManager?.focusWindow(window)
                log("★ AUTO-FOCUS DIALOG Oui/Non → \(window.label)", pid: window.pid, source: .spike)
                return
            }
        }
    }

    /// Count orange pixels in an already-captured CGImage within a given region
    private func countOrangeInImage(_ image: CGImage, region: (xStart: CGFloat, xEnd: CGFloat, yStart: CGFloat, yEnd: CGFloat)) -> (Int, Int) {
        let imgWidth = image.width
        let imgHeight = image.height

        let regionX = Int(CGFloat(imgWidth) * region.xStart)
        let regionY = Int(CGFloat(imgHeight) * region.yStart)
        let regionW = Int(CGFloat(imgWidth) * (region.xEnd - region.xStart))
        let regionH = Int(CGFloat(imgHeight) * (region.yEnd - region.yStart))

        guard regionW > 0, regionH > 0,
              regionX + regionW <= imgWidth,
              regionY + regionH <= imgHeight else { return (0, 0) }

        let bytesPerPixel = 4
        let bytesPerRow = regionW * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: regionW * regionH * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: regionW,
            height: regionH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0) }

        context.draw(image, in: CGRect(
            x: -CGFloat(regionX),
            y: -CGFloat(imgHeight - regionY - regionH),
            width: CGFloat(imgWidth),
            height: CGFloat(imgHeight)
        ))

        var count = 0
        let totalPixels = regionW * regionH
        var i = 0
        while i < pixelData.count - 3 {
            let r = pixelData[i]
            let g = pixelData[i + 1]
            let b = pixelData[i + 2]
            if r > 180 && g > 60 && g < 180 && b < 80 {
                count += 1
            }
            i += 4
        }

        return (count, totalPixels)
    }

    /// Helper to save a CGImage to disk as PNG
    private func saveImage(_ cgImage: CGImage, to path: String) {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Orange Pixel Detection

    /// Count orange-colored pixels in a given region of a window
    /// Returns (orangeCount, totalPixels)
    private func countOrangePixelsInRegion(for window: TrackedWindow, region: (xStart: CGFloat, xEnd: CGFloat, yStart: CGFloat, yEnd: CGFloat)) -> (Int, Int) {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            window.id,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else { return (0, 0) }

        let imgWidth = image.width
        let imgHeight = image.height

        let regionX = Int(CGFloat(imgWidth) * region.xStart)
        let regionY = Int(CGFloat(imgHeight) * region.yStart)
        let regionW = Int(CGFloat(imgWidth) * (region.xEnd - region.xStart))
        let regionH = Int(CGFloat(imgHeight) * (region.yEnd - region.yStart))

        guard regionW > 0, regionH > 0,
              regionX + regionW <= imgWidth,
              regionY + regionH <= imgHeight else { return (0, 0) }

        let bytesPerPixel = 4
        let bytesPerRow = regionW * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: regionW * regionH * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: regionW,
            height: regionH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0) }

        context.draw(image, in: CGRect(
            x: -CGFloat(regionX),
            y: -CGFloat(imgHeight - regionY - regionH),
            width: CGFloat(imgWidth),
            height: CGFloat(imgHeight)
        ))

        // Count orange pixels
        // Orange in RGB: R > 180, G between 60-180, B < 80
        var count = 0
        let totalPixels = regionW * regionH
        var i = 0
        while i < pixelData.count - 3 {
            let r = pixelData[i]
            let g = pixelData[i + 1]
            let b = pixelData[i + 2]

            if r > 180 && g > 60 && g < 180 && b < 80 {
                count += 1
            }
            i += 4
        }

        return (count, totalPixels)
    }

    /// Convenience for combat detection (uses flagRegion)
    private func countOrangePixels(for window: TrackedWindow) -> (Int, Int) {
        return countOrangePixelsInRegion(for: window, region: (flagRegion.xStart, flagRegion.xEnd, flagRegion.yStart, flagRegion.yEnd))
    }

    // MARK: - Logging

    private func log(_ message: String, pid: pid_t, source: LogSource) {
        notifService?.appendLogEntry(LogEntry(
            timestamp: Date(),
            message: message,
            pid: pid,
            source: source
        ), for: pid)
    }
}
