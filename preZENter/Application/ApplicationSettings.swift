import Foundation

final class ApplicationSettings {

    static let shared = ApplicationSettings()

    enum Defaults {
        static let coreGraphicsFrameRate = 35
    }

    private enum Key {
        static let keepsMacAwake = "keepsMacAwake"
        static let promptsForExternalDisplay = "promptsForExternalDisplay"
        static let forcesCoreGraphicsCapture = "forcesCoreGraphicsCapture"
        static let coreGraphicsFrameRate = "coreGraphicsFrameRate"
        static let hidesCapturedMouseCursor = "hidesCapturedMouseCursor"
        static let bringsSelectedApplicationWindowToFront = "bringsSelectedApplicationWindowToFront"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.keepsMacAwake: false,
                                     Key.promptsForExternalDisplay: false,
                                     Key.forcesCoreGraphicsCapture: false,
                                     Key.coreGraphicsFrameRate: Defaults.coreGraphicsFrameRate,
                                     Key.hidesCapturedMouseCursor: false,
                                     Key.bringsSelectedApplicationWindowToFront: true])
    }

    var keepsMacAwake: Bool {
        get { return defaults.bool(forKey: Key.keepsMacAwake) }
        set { set(newValue, forKey: Key.keepsMacAwake, notification: .generalSettingsDidChange) }
    }

    var promptsForExternalDisplay: Bool {
        get { return defaults.bool(forKey: Key.promptsForExternalDisplay) }
        set { set(newValue, forKey: Key.promptsForExternalDisplay, notification: .generalSettingsDidChange) }
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

}

extension Notification.Name {
    static let generalSettingsDidChange = Notification.Name("generalSettingsDidChange")
    static let captureSettingsDidChange = Notification.Name("captureSettingsDidChange")
}
