import Foundation

final class ApplicationSettings {

    static let shared = ApplicationSettings()

    enum Defaults {
        static let coreGraphicsFrameRate = 35
        static let transitionDuration: TimeInterval = 0.25
        static let outputVolume = 100
    }

    private enum Key {
        static let keepsMacAwake = "keepsMacAwake"
        static let promptsForExternalDisplay = "promptsForExternalDisplay"
        static let automaticallyMovesLiveWindow = "automaticallyMovesLiveWindow"
        static let forcesCoreGraphicsCapture = "forcesCoreGraphicsCapture"
        static let coreGraphicsFrameRate = "coreGraphicsFrameRate"
        static let hidesCapturedMouseCursor = "hidesCapturedMouseCursor"
        static let bringsSelectedApplicationWindowToFront = "bringsSelectedApplicationWindowToFront"
        static let fadesBetweenContents = "fadesBetweenContents"
        static let transitionDuration = "transitionDuration"
        static let outputVolume = "outputVolume"
        static let mutesVideoDeviceAudio = "mutesVideoDeviceAudio"
        static let mutesIOSDeviceAudio = "mutesIOSDeviceAudio"
        static let usesMonoAudioOutput = "usesMonoAudioOutput"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.keepsMacAwake: false,
                                     Key.promptsForExternalDisplay: false,
                                     Key.automaticallyMovesLiveWindow: false,
                                     Key.forcesCoreGraphicsCapture: false,
                                     Key.coreGraphicsFrameRate: Defaults.coreGraphicsFrameRate,
                                     Key.hidesCapturedMouseCursor: false,
                                     Key.bringsSelectedApplicationWindowToFront: true,
                                     Key.fadesBetweenContents: true,
                                     Key.transitionDuration: Defaults.transitionDuration,
                                     Key.outputVolume: Defaults.outputVolume,
                                     Key.mutesVideoDeviceAudio: false,
                                     Key.mutesIOSDeviceAudio: false,
                                     Key.usesMonoAudioOutput: false])
        if defaults.bool(forKey: Key.promptsForExternalDisplay),
           defaults.bool(forKey: Key.automaticallyMovesLiveWindow) {
            defaults.set(false, forKey: Key.automaticallyMovesLiveWindow)
        }
    }

    var keepsMacAwake: Bool {
        get { return defaults.bool(forKey: Key.keepsMacAwake) }
        set { set(newValue, forKey: Key.keepsMacAwake, notification: .generalSettingsDidChange) }
    }

    var promptsForExternalDisplay: Bool {
        get { return defaults.bool(forKey: Key.promptsForExternalDisplay) }
        set {
            guard promptsForExternalDisplay != newValue else { return }
            defaults.set(newValue, forKey: Key.promptsForExternalDisplay)
            if newValue { defaults.set(false, forKey: Key.automaticallyMovesLiveWindow) }
            NotificationCenter.default.post(name: .generalSettingsDidChange, object: self)
        }
    }

    var automaticallyMovesLiveWindow: Bool {
        get { return defaults.bool(forKey: Key.automaticallyMovesLiveWindow) }
        set {
            guard automaticallyMovesLiveWindow != newValue else { return }
            defaults.set(newValue, forKey: Key.automaticallyMovesLiveWindow)
            if newValue { defaults.set(false, forKey: Key.promptsForExternalDisplay) }
            NotificationCenter.default.post(name: .generalSettingsDidChange, object: self)
        }
    }

    var forcesCoreGraphicsCapture: Bool {
        get { return defaults.bool(forKey: Key.forcesCoreGraphicsCapture) }
        set { set(newValue, forKey: Key.forcesCoreGraphicsCapture, notification: .captureSettingsDidChange) }
    }

    var coreGraphicsFrameRate: Int {
        get { return max(1, min(defaults.integer(forKey: Key.coreGraphicsFrameRate), 240)) }
        set {
            let validatedValue = max(1, min(newValue, 240))
            set(validatedValue, forKey: Key.coreGraphicsFrameRate, notification: .captureSettingsDidChange)
        }
    }

    var hidesCapturedMouseCursor: Bool {
        get { return defaults.bool(forKey: Key.hidesCapturedMouseCursor) }
        set { set(newValue, forKey: Key.hidesCapturedMouseCursor, notification: .captureSettingsDidChange) }
    }

    var bringsSelectedApplicationWindowToFront: Bool {
        get { return defaults.bool(forKey: Key.bringsSelectedApplicationWindowToFront) }
        set {
            guard defaults.bool(forKey: Key.bringsSelectedApplicationWindowToFront) != newValue else { return }
            defaults.set(newValue, forKey: Key.bringsSelectedApplicationWindowToFront)
        }
    }

    var fadesBetweenContents: Bool {
        get { return defaults.bool(forKey: Key.fadesBetweenContents) }
        set { set(newValue, forKey: Key.fadesBetweenContents, notification: .presentingSettingsDidChange) }
    }

    var transitionDuration: TimeInterval {
        get { return max(0, min(defaults.double(forKey: Key.transitionDuration), 10)) }
        set {
            let validatedValue = max(0, min(newValue, 10))
            set(validatedValue, forKey: Key.transitionDuration, notification: .presentingSettingsDidChange)
        }
    }

    var outputVolume: Int {
        get { return max(0, min(defaults.integer(forKey: Key.outputVolume), 100)) }
        set {
            let validatedValue = max(0, min(newValue, 100))
            set(validatedValue, forKey: Key.outputVolume, notification: .audioSettingsDidChange)
        }
    }

    var mutesVideoDeviceAudio: Bool {
        get { return defaults.bool(forKey: Key.mutesVideoDeviceAudio) }
        set { set(newValue, forKey: Key.mutesVideoDeviceAudio, notification: .audioSettingsDidChange) }
    }

    var mutesIOSDeviceAudio: Bool {
        get { return defaults.bool(forKey: Key.mutesIOSDeviceAudio) }
        set { set(newValue, forKey: Key.mutesIOSDeviceAudio, notification: .audioSettingsDidChange) }
    }

    var usesMonoAudioOutput: Bool {
        get { return defaults.bool(forKey: Key.usesMonoAudioOutput) }
        set { set(newValue, forKey: Key.usesMonoAudioOutput, notification: .audioSettingsDidChange) }
    }

    private func set(_ value: Bool, forKey key: String, notification: Notification.Name) {
        guard defaults.bool(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: notification, object: self)
    }

    private func set(_ value: Int, forKey key: String, notification: Notification.Name) {
        guard defaults.integer(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: notification, object: self)
    }

    private func set(_ value: Double, forKey key: String, notification: Notification.Name) {
        guard defaults.double(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: notification, object: self)
    }

}

extension Notification.Name {
    static let generalSettingsDidChange = Notification.Name("generalSettingsDidChange")
    static let captureSettingsDidChange = Notification.Name("captureSettingsDidChange")
    static let presentingSettingsDidChange = Notification.Name("presentingSettingsDidChange")
    static let audioSettingsDidChange = Notification.Name("audioSettingsDidChange")
}
