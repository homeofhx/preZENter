import Cocoa

class IdleScreen: NSObject {
    
    public static func renderIdleScreenContents(for size: NSSize) -> NSImage {
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
                                                           options: [.usesLineFragmentOrigin,
                                                                     .usesFontLeading]).height) + 5
        
        if showTime {
            let timerFontSize = max(fontSize * 0.65, 24)
            let timeAttributes = NSAttributedString(string: DateFormatter.hhmmss.string(from: Date()),
                                                    attributes: [.font: NSFont
                                                        .monospacedDigitSystemFont(ofSize: timerFontSize,
                                                                                   weight: .regular),
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
    
    // MARK: - Settings dialog
    
    public func showIdleScreenSettings() {
        let (accessory, textView, sizeField) = buildAccessoryView()
        
        let alert = NSAlert()
        alert.messageText = "Idle Screen Settings"
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset to Default")
        
        let timerButton = alert.addButton(withTitle: showTime ? "Hide Time" : "Show Time")
        alert.layout()
        alert.window.initialFirstResponder = textView
        
        let timerState = Box(showTime)
        let handler = ButtonActionHandler {
            timerState.value.toggle()
            timerButton.title = timerState.value ? "Hide Time" : "Show Time" }
        timerButton.target = handler
        timerButton.action = #selector(ButtonActionHandler.invoke(_:))
        objc_setAssociatedObject(alert, &ButtonActionHandler.key, handler, .OBJC_ASSOCIATION_RETAIN)   // Retain handler for the duration of the modal (alert holds no strong ref to it).
        
        switch alert.runModal() {
        case .alertFirstButtonReturn: applySettings(from: textView, sizeField: sizeField, isTimerOn: timerState.value)   // Save
        case .alertThirdButtonReturn: resetToDefaults()   // Reset to Default
        default: break   // Cancel
        }
    }
    
    private func buildAccessoryView() -> (view: NSView, textView: NSTextView, sizeField: NSTextField) {
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 125))
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 48, width: 300, height: 78))
        scrollView.borderType = .bezelBorder
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 78))
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.string = message
        scrollView.documentView = textView
        accessory.addSubview(scrollView)
        
        let sizeLabel = NSTextField(labelWithString: "Font size (pt):")
        sizeLabel.frame = NSRect(x: 0, y: 16, width: 90, height: 18)
        accessory.addSubview(sizeLabel)
        
        let sizeField = NSTextField(frame: NSRect(x: 95, y: 12, width: 80, height: 24))
        sizeField.stringValue = String(format: "%.0f", messageFontSize)
        sizeField.placeholderString = "85"
        accessory.addSubview(sizeField)
        
        return (accessory, textView, sizeField)
    }
    
    private func applySettings(from textView: NSTextView, sizeField: NSTextField, isTimerOn: Bool) {
        let newMessage = textView.string.trimmingCharacters(in: .newlines)
        let newSize = CGFloat(sizeField.doubleValue)
        message = newMessage.isEmpty ? "" : newMessage
        messageFontSize = newSize > 0 ? newSize : 85
        showTime = isTimerOn
        NotificationCenter.default.post(name: .idleScreenSettingsDidChange, object: nil)
    }
    
    private func resetToDefaults() {
        message = "Program about to begin.\nPlease stand by."
        messageFontSize = 85
        showTime = false
        NotificationCenter.default.post(name: .idleScreenSettingsDidChange, object: nil)
    }
    
}

// MARK: - Helpers

private final class Box<T> {
    
    var value: T
    
    init(_ value: T) {
        self.value = value
    }
    
}

private final class ButtonActionHandler: NSObject {
    
    static var key = 0   // used as an objc_setAssociatedObject key
    
    private let action: () -> Void
    
    init(_ action: @escaping () -> Void) {
        self.action = action
    }
    
    @objc func invoke(_ sender: Any) {
        action()
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
