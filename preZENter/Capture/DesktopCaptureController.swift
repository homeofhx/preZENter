import Cocoa
import ApplicationServices

protocol DesktopCapturer: AnyObject {
    var delegate: DesktopCapturerDelegate? { get set }
    func start()
    func stop()
}

protocol DesktopCapturerDelegate: AnyObject {
    func capturer(_ capturer: DesktopCapturer, didCapture image: NSImage)
    func capturerDidLoseSource(_ capturer: DesktopCapturer)
}

final class DesktopCaptureController: DesktopCapturerDelegate {

    private var activeCapturer: DesktopCapturer?
    private var onFrame: ((NSImage) -> Void)?
    private var onSourceLost: (() -> Void)?

    func start(source: ContentSource,
               activatesWindow: Bool = true,
               onFrame: @escaping (NSImage) -> Void,
               onSourceLost: @escaping () -> Void) {
        stop()

        let settings = ApplicationSettings.shared
        let frameRate = settings.coreGraphicsFrameRate
        let showsCursor = !settings.hidesCapturedMouseCursor
        let capturer: DesktopCapturer
        switch source {
        case .applicationWindow(let windowID):
            if activatesWindow && settings.bringsSelectedApplicationWindowToFront {
                DesktopCaptureController.bringWindowToFront(windowID: windowID)
            }
            if #available(macOS 12.3, *), !settings.forcesCoreGraphicsCapture {
                capturer = ScreenCaptureKitWindowCapturer(windowID: windowID, fallbackFrameRate: frameRate, showsCursor: showsCursor)
            } else {
                capturer = CoreGraphicsWindowCapturer(windowID: windowID, frameRate: frameRate, showsCursor: showsCursor)
            }
        case .screen(let displayID):
            if #available(macOS 12.3, *), !settings.forcesCoreGraphicsCapture {
                capturer = ScreenCaptureKitScreenCapturer(displayID: displayID, fallbackFrameRate: frameRate, showsCursor: showsCursor)
            } else {
                capturer = CoreGraphicsScreenCapturer(displayID: displayID, frameRate: frameRate, showsCursor: showsCursor)
            }
        case .videoDevice, .iOSDevice:
            preconditionFailure("DesktopCaptureController only captures windows and screens")
        }

        self.onFrame = onFrame
        self.onSourceLost = onSourceLost
        activeCapturer = capturer
        capturer.delegate = self
        capturer.start()
    }

    func stop() {
        let capturer = activeCapturer
        activeCapturer = nil
        onFrame = nil
        onSourceLost = nil
        capturer?.delegate = nil
        capturer?.stop()
    }

    func capturer(_ capturer: DesktopCapturer, didCapture image: NSImage) {
        guard capturer === activeCapturer else { return }
        onFrame?(image)
    }

    func capturerDidLoseSource(_ capturer: DesktopCapturer) {
        guard capturer === activeCapturer else { return }
        onSourceLost?()
    }

    private static func bringWindowToFront(windowID: CGWindowID) {
        guard let windowInfo = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
            as? [[String: AnyObject]])?.first,
              let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              let application = NSRunningApplication(processIdentifier: ownerPID) else { return }

        let applicationElement = AXUIElementCreateApplication(ownerPID)

        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: application)
            application.activate(from: NSRunningApplication.current, options: [])
        } else {
            application.activate(options: [.activateIgnoringOtherApps])
        }

        AXUIElementSetAttributeValue(applicationElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        raiseWindow(windowID: windowID, applicationElement: applicationElement)
    }

    private static func raiseWindow(windowID: CGWindowID, applicationElement: AXUIElement) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        for window in windows {
            var candidateID: CGWindowID = 0
            guard _AXUIElementGetWindow(window, &candidateID) == .success,
                  candidateID == windowID else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            break
        }
    }

}

@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: inout CGWindowID) -> AXError
