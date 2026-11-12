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
    
    var message: String {
        get { defaults.string(forKey: Keys.message) ?? "Program about to begin.\nPlease stand by." }
        set { defaults.set(newValue, forKey: Keys.message) }
    }
    
    var messageFontSize: CGFloat {
        get {
            let size = defaults.double(forKey: Keys.fontSize)
            return size > 0 ? CGFloat(size) : 85
        }
        set { defaults.set(Double(newValue), forKey: Keys.fontSize) }
    }
    
    var showTime: Bool {
        get { defaults.object(forKey: Keys.showTime) == nil ? false : defaults.bool(forKey: Keys.showTime) }
        set { defaults.set(newValue, forKey: Keys.showTime) }
    }
    
    private init() {}
    
    func update(message: String, fontSize: CGFloat, showTime: Bool) {
        self.message = message.trimmingCharacters(in: .newlines)
        messageFontSize = fontSize > 0 ? fontSize : 85
        self.showTime = showTime
        NotificationCenter.default.post(name: .idleScreenSettingsDidChange, object: nil)
    }
    
    func resetToDefaults() {
        message = "Program about to begin.\nPlease stand by."
        messageFontSize = 85
        showTime = false
        NotificationCenter.default.post(name: .idleScreenSettingsDidChange, object: nil)
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
}
