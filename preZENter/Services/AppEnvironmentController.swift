import Cocoa
import CoreGraphics

final class AppEnvironmentController {

    var onExternalDisplayConnected: ((CGDirectDisplayID) -> Void)?

    private var keepAwakeActivity: NSObjectProtocol?
    private var knownDisplayIDs = Set<CGDirectDisplayID>()
    private var settingsObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?

    func start() {
        stopObservers()
        knownDisplayIDs = Set(NSScreen.screens.compactMap { $0.displayID })
        applySleepPreventionSetting()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .generalSettingsDidChange,
            object: ApplicationSettings.shared,
            queue: .main) { [weak self] _ in
                self?.applySleepPreventionSetting()
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.screenParametersDidChange()
        }
    }

    func stop() {
        stopObservers()
        stopKeepAwakeActivity()
    }

    private func applySleepPreventionSetting() {
        if ApplicationSettings.shared.keepsMacAwake {
            guard keepAwakeActivity == nil else { return }
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled],
                                                                      reason: "preZENter is presenting")
        } else {
            stopKeepAwakeActivity()
        }
    }

    private func stopKeepAwakeActivity() {
        guard let activity = keepAwakeActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        keepAwakeActivity = nil
    }

    private func screenParametersDidChange() {
        let currentScreens = NSScreen.screens
        let currentDisplayIDs = Set(currentScreens.compactMap { $0.displayID })
        let connectedDisplayIDs = currentDisplayIDs.subtracting(knownDisplayIDs)
        knownDisplayIDs = currentDisplayIDs

        guard ApplicationSettings.shared.promptsForExternalDisplay else { return }
        guard let displayID = connectedDisplayIDs.first(where: { CGDisplayIsBuiltin($0) == 0 }) else { return }
        onExternalDisplayConnected?(displayID)
    }

    private func stopObservers() {
        if let observer = settingsObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = displayObserver { NotificationCenter.default.removeObserver(observer) }
        settingsObserver = nil
        displayObserver = nil
    }

}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
