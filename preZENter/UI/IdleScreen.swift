import Cocoa

enum IdleScreen {
    
    static func renderIdleScreenContents(for size: NSSize) -> NSImage {
        let message = IdleScreenSettings.shared.message
        let fontSize = IdleScreenSettings.shared.messageFontSize
        let showTime = IdleScreenSettings.shared.showTime
        
        let hPad: CGFloat = 48
        let maxWidth = max(size.width - hPad * 2, 1)
        
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byWordWrapping
        
        let messageAttrs = NSAttributedString(string: message,
                                              attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                                                           .foregroundColor: NSColor.white,
                                                           .paragraphStyle: centered])
        let messageHeight = ceil(messageAttrs.boundingRect(with: NSSize(width: maxWidth, height: size.height),
                                                           options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 5
        
        if showTime {
            let timerFontSize = max(fontSize * 0.65, 24)
            let timeAttributes = NSAttributedString(string: DateFormatter.hhmmss.string(from: Date()),
                                                    attributes: [.font: NSFont
                                                        .monospacedDigitSystemFont(ofSize: timerFontSize, weight: .regular),
                                                                 .foregroundColor: NSColor.white.withAlphaComponent(0.75),
                                                                 .paragraphStyle: centered])
            let timeHeight = ceil(timeAttributes.boundingRect(with: NSSize(width: maxWidth, height: size.height),
                                                              options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 5
            
            let gap = fontSize * 0.2
            let totalHeight = messageHeight + gap + timeHeight
            let blockStartY = (size.height - totalHeight) / 2
            
            messageAttrs.draw(with: NSRect(x: hPad, y: blockStartY + timeHeight + gap, width: maxWidth, height: messageHeight),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
            timeAttributes.draw(with: NSRect(x: hPad, y: blockStartY, width: maxWidth, height: timeHeight),
                                options: [.usesLineFragmentOrigin, .usesFontLeading])
        } else {
            messageAttrs.draw(with: NSRect(x: hPad, y: (size.height - messageHeight) / 2, width: maxWidth, height: messageHeight),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        
        canvas.unlockFocus()
        return canvas
    }
    
}

// MARK: - Idle Screen settings
class IdleScreenSettings {
    
    static let shared = IdleScreenSettings()
    
    private enum Keys {
        static let message = "idleScreenMessage"
        static let fontSize = "idleScreenFontSize"
        static let showTime = "idleScreenShowTime"
    }
    
    private let defaults = UserDefaults.standard

    private enum Default {
        static let message = "Program about to begin.\nPlease stand by."
        static let fontSize: CGFloat = 85
        static let showTime = false
    }
    
    var message: String { return defaults.string(forKey: Keys.message) ?? Default.message }
    
    var messageFontSize: CGFloat {
        let size = defaults.double(forKey: Keys.fontSize)
        return size > 0 ? max(1, min(CGFloat(size), 500)) : Default.fontSize
    }
    
    var showTime: Bool {
        return defaults.object(forKey: Keys.showTime) == nil ? Default.showTime : defaults.bool(forKey: Keys.showTime)
    }
    
    private init() {}
    
    func updateMessage(_ message: String) {
        guard self.message != message else { return }
        defaults.set(message, forKey: Keys.message)
        notifyChange()
    }
    
    func updateFontSize(_ fontSize: CGFloat) {
        let validatedSize = max(1, min(fontSize, 500))
        guard messageFontSize != validatedSize else { return }
        defaults.set(Double(validatedSize), forKey: Keys.fontSize)
        notifyChange()
    }
    
    func updateShowTime(_ showTime: Bool) {
        guard self.showTime != showTime else { return }
        defaults.set(showTime, forKey: Keys.showTime)
        notifyChange()
    }
    
    private func notifyChange() {
        NotificationCenter.default.post(name: .idleScreenSettingsDidChange, object: nil)
    }
    
    func resetToDefaults() {
        defaults.set(Default.message, forKey: Keys.message)
        defaults.set(Double(Default.fontSize), forKey: Keys.fontSize)
        defaults.set(Default.showTime, forKey: Keys.showTime)
        notifyChange()
    }
    
}

enum LiveWindowTextPosition: Int {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    
    static let all: [LiveWindowTextPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    
    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

final class LiveWindowTextSettings {
    
    static let shared = LiveWindowTextSettings()
    
    enum Default {
        static let fontSize: CGFloat = 12
        static let position = LiveWindowTextPosition.bottomRight
    }
    
    private enum Key {
        static let showsPresentedSourceName = "liveWindowShowsPresentedSourceName"
        static let showsCustomText = "liveWindowShowsCustomText"
        static let customText = "liveWindowCustomText"
        static let fontSize = "liveWindowTextFontSize"
        static let position = "liveWindowTextPosition"
    }
    
    private let defaults: UserDefaults
    
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.showsPresentedSourceName: false,
                                     Key.showsCustomText: false,
                                     Key.customText: "",
                                     Key.fontSize: Double(Default.fontSize),
                                     Key.position: Default.position.rawValue])
        if defaults.bool(forKey: Key.showsPresentedSourceName),
           defaults.bool(forKey: Key.showsCustomText) {
            defaults.set(false, forKey: Key.showsCustomText)
        }
    }
    
    var showsPresentedSourceName: Bool { return defaults.bool(forKey: Key.showsPresentedSourceName) }
    var showsCustomText: Bool { return defaults.bool(forKey: Key.showsCustomText) }
    var customText: String { return defaults.string(forKey: Key.customText) ?? "" }
    var fontSize: CGFloat { return max(1, min(CGFloat(defaults.double(forKey: Key.fontSize)), 500)) }
    var position: LiveWindowTextPosition {
        return LiveWindowTextPosition(rawValue: defaults.integer(forKey: Key.position)) ?? Default.position
    }
    
    func updateShowsPresentedSourceName(_ isEnabled: Bool) {
        guard showsPresentedSourceName != isEnabled || (isEnabled && showsCustomText) else { return }
        defaults.set(isEnabled, forKey: Key.showsPresentedSourceName)
        if isEnabled { defaults.set(false, forKey: Key.showsCustomText) }
        notifyChange()
    }
    
    func updateShowsCustomText(_ isEnabled: Bool) {
        guard showsCustomText != isEnabled || (isEnabled && showsPresentedSourceName) else { return }
        defaults.set(isEnabled, forKey: Key.showsCustomText)
        if isEnabled { defaults.set(false, forKey: Key.showsPresentedSourceName) }
        notifyChange()
    }
    
    func updateCustomText(_ text: String) {
        let singleLineText = text.replacingOccurrences(of: "\n", with: " ")
        guard customText != singleLineText else { return }
        defaults.set(singleLineText, forKey: Key.customText)
        notifyChange()
    }
    
    func updateFontSize(_ fontSize: CGFloat) {
        let validatedSize = max(1, min(fontSize, 500))
        guard self.fontSize != validatedSize else { return }
        defaults.set(Double(validatedSize), forKey: Key.fontSize)
        notifyChange()
    }
    
    func updatePosition(_ position: LiveWindowTextPosition) {
        guard self.position != position else { return }
        defaults.set(position.rawValue, forKey: Key.position)
        notifyChange()
    }
    
    func resetTextAppearance() {
        defaults.set(Double(Default.fontSize), forKey: Key.fontSize)
        defaults.set(Default.position.rawValue, forKey: Key.position)
        notifyChange()
    }
    
    private func notifyChange() {
        NotificationCenter.default.post(name: .liveWindowTextSettingsDidChange, object: nil)
    }

}

// MARK: - Timer formatter

private extension DateFormatter {
    static let hhmmss: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter
    }()
}

extension Notification.Name {
    static let idleScreenSettingsDidChange = Notification.Name("idleScreenSettingsDidChange")
    static let liveWindowTextSettingsDidChange = Notification.Name("liveWindowTextSettingsDidChange")
}
