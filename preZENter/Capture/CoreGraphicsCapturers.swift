import Cocoa
import CoreGraphics

final class CoreGraphicsWindowCapturer: DesktopCapturer {

    weak var delegate: DesktopCapturerDelegate?

    private let windowID: CGWindowID
    private var captureTimer: Timer?

    init(windowID: CGWindowID) {
        self.windowID = windowID
    }

    func start() {
        stop()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
        if let timer = captureTimer { RunLoop.current.add(timer, forMode: .common) }
    }

    func stop() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    private func captureFrame() {
        guard let imageReference = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.bestResolution, .boundsIgnoreFraming]) else {
            stop()
            delegate?.capturerDidLoseSource(self)
            return
        }

        let image = NSImage(cgImage: imageReference, size: .zero)
        guard let bounds = windowBounds() else {
            delegate?.capturer(self, didCapture: image)
            return
        }

        delegate?.capturer(self, didCapture: image.drawingCursor(for: bounds))
    }

    private func windowBounds() -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
            as? [[String: AnyObject]],
              let window = windowInfo.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
              let boundsDictionary = window[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
    }

}

final class CoreGraphicsScreenCapturer: DesktopCapturer {

    weak var delegate: DesktopCapturerDelegate?

    private let displayID: CGDirectDisplayID
    private var captureTimer: Timer?
    private var consecutiveFailures = 0
    private static let maximumFailures = 5

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    func start() {
        stop()
        consecutiveFailures = 0
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
        if let timer = captureTimer { RunLoop.current.add(timer, forMode: .common) }
    }

    func stop() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    private func captureFrame() {
        guard let imageReference = CGDisplayCreateImage(displayID) else {
            consecutiveFailures += 1
            if consecutiveFailures >= CoreGraphicsScreenCapturer.maximumFailures {
                stop()
                delegate?.capturerDidLoseSource(self)
            }

            return
        }

        consecutiveFailures = 0
        let image = NSImage(cgImage: imageReference, size: .zero)
        delegate?.capturer(self, didCapture: image.drawingCursor(for: CGDisplayBounds(displayID)))
    }

}

extension NSImage {
    func drawingCursor(for sourceBounds: CGRect) -> NSImage {
        guard let event = CGEvent(source: nil) else { return self }
        let mouseLocation = event.location
        guard sourceBounds.contains(mouseLocation) else { return self }

        let cursor = NSCursor.arrow
        let cursorImage = cursor.image
        let hotSpot = cursor.hotSpot
        let result = NSImage(size: size)
        result.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))

        let scaleX = size.width / sourceBounds.width
        let scaleY = size.height / sourceBounds.height
        let x = (mouseLocation.x - sourceBounds.minX - hotSpot.x) * scaleX
        let y = size.height - (mouseLocation.y - sourceBounds.minY - hotSpot.y) * scaleY - cursorImage.size.height
        cursorImage.draw(at: NSPoint(x: x, y: y), from: .zero, operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
