import Cocoa
import AVFoundation
import ApplicationServices
import CoreGraphics

final class PermissionCoordinator {

    weak var presentingWindow: NSWindow?

    private var didRequestAccessibilityThisSession = false
    private var pendingAlerts: [PendingAlert] = []
    private var isShowingPermissionAlert = false

    func ensurePermissions(for source: ContentSource, completion: @escaping (Bool) -> Void) {
        switch source {
        case .applicationWindow:
            ensureScreenCapturePermission { [weak self] granted in
                if granted { self?.requestAccessibilityPermissionIfNeeded() }
                completion(granted)
            }
        case .screen:
            ensureScreenCapturePermission(completion: completion)
        case .videoDevice, .iOSDevice:
            ensureCaptureDevicePermissions(completion: completion)
        }
    }

    func ensureScreenCapturePermission(completion: @escaping (Bool) -> Void) {
        guard #available(macOS 10.15, *) else {
            completion(true)
            return
        }

        guard !CGPreflightScreenCaptureAccess() else {
            completion(true)
            return
        }

        if CGRequestScreenCaptureAccess() {
            completion(true)
        } else {
            showMissingPermission(.screenRecording, completion: completion)
        }
    }

    private func ensureCaptureDevicePermissions(completion: @escaping (Bool) -> Void) {
        ensureMediaPermission(.video, capability: .camera) { [weak self] cameraGranted in
            guard let self = self, cameraGranted else {
                completion(false)
                return
            }

            self.ensureMediaPermission(.audio, capability: .microphone, completion: completion)
        }
    }

    private func ensureMediaPermission(_ mediaType: AVMediaType, capability: Capability, completion: @escaping (Bool) -> Void) {
        guard #available(macOS 10.14, *) else {
            completion(true)
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: mediaType) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else {
                        completion(false)
                        return
                    }
                    if granted {
                        completion(true)
                    } else {
                        self.showMissingPermission(capability, completion: completion)
                    }
                }
            }
        case .denied, .restricted:
            showMissingPermission(capability, completion: completion)
        default:
            completion(capability.allowsContinuationWhenDenied)
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard ApplicationSettings.shared.bringsSelectedApplicationWindowToFront,
              !AXIsProcessTrusted(),
              !didRequestAccessibilityThisSession else { return }

        didRequestAccessibilityThisSession = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func showMissingPermission(_ capability: Capability, completion: @escaping (Bool) -> Void) {
        if let index = pendingAlerts.firstIndex(where: { $0.capability == capability }) {
            pendingAlerts[index].completions.append(completion)
        } else {
            pendingAlerts.append(PendingAlert(capability: capability, completions: [completion]))
        }
        presentNextPermissionAlertIfNeeded()
    }

    private func presentNextPermissionAlertIfNeeded() {
        guard !isShowingPermissionAlert,
              let capability = pendingAlerts.first?.capability else { return }

        isShowingPermissionAlert = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = capability.alertTitle
        alert.informativeText = capability.alertMessage
        alert.addButton(withTitle: systemSettingsButtonTitle)
        alert.addButton(withTitle: "Not Now")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self else { return }
            if response == .alertFirstButtonReturn,
               let url = URL(string: capability.settingsURLString) {
                NSWorkspace.shared.open(url)
            }

            let pendingAlert = self.pendingAlerts.removeFirst()
            self.isShowingPermissionAlert = false
            pendingAlert.completions.forEach { $0(capability.allowsContinuationWhenDenied) }
            self.presentNextPermissionAlertIfNeeded()
        }

        if let window = presentingWindow, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private var systemSettingsButtonTitle: String {
        if #available(macOS 13.0, *) { return "Open System Settings" }
        return "Open System Preferences"
    }

}

private extension PermissionCoordinator {

    struct PendingAlert {
        let capability: Capability
        var completions: [(Bool) -> Void]
    }

    enum Capability: Equatable {
        case screenRecording
        case camera
        case microphone

        var allowsContinuationWhenDenied: Bool { return self == .microphone }

        var alertTitle: String {
            switch self {
            case .screenRecording: return "Screen Recording Permission Required"
            case .camera: return "Camera Permission Required"
            case .microphone: return "Microphone Permission May Required"
            }
        }

        var alertMessage: String {
            switch self {
            case .screenRecording:
                return "preZENter needs Screen Recording permission to capture application windows and displays."
            case .camera:
                return "preZENter needs Camera permission to stream video capture devices."
            case .microphone:
                return "preZENter needs Microphone permission to stream audio from video capture devices. The Microphone permission is optional; if you prefer not to stream audio from video capture devices, you may deny it."
            }
        }

        var settingsURLString: String {
            let pane: String
            switch self {
            case .screenRecording: pane = "Privacy_ScreenCapture"
            case .camera: pane = "Privacy_Camera"
            case .microphone: pane = "Privacy_Microphone"
            }
            return "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        }
    }

}
