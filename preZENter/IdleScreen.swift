import Cocoa

class IdleScreenSettings {
    
    static let shared = IdleScreenSettings()
    
    private enum keys {
        static let message = "idleScreenMessage"
        static let fontSize = "idleScreenFontSize"
        static let showTime = "idleScreenShowTime"
    }
    
    private let defaults = UserDefaults.standard
    
    var message: String {
        get { return defaults.string(forKey: keys.message) ?? "We will start shortly.\nPlease stand by." }
        set { defaults.set(newValue, forKey: keys.message) }
    }
    
    var messageFontSize: CGFloat {
        get {
            let v = defaults.double(forKey: keys.fontSize)
            return v > 0 ? CGFloat(v) : 100
        }
        set { defaults.set(Double(newValue), forKey: keys.fontSize) }
    }
    
    var showTime: Bool {
        get { return defaults.object(forKey: keys.showTime) == nil ? false : defaults.bool(forKey: keys.showTime) }
        set { defaults.set(newValue, forKey: keys.showTime) }
    }
    
    private init() {}
    
    public func showIdleScreenSettings() {
        // Customizable layout for the settings box
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 125))
        
        // Customizable text on Idle Screen
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 48, width: 300, height: 78))
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 78))
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.string = message
        scrollView.documentView = textView
        accessory.addSubview(scrollView)
        
        // Text size for customizable text
        let sizeLabel = NSTextField(labelWithString: "Font size (pt):")
        sizeLabel.frame = NSRect(x: 0, y: 16, width: 90, height: 18)
        accessory.addSubview(sizeLabel)
        let sizeField = NSTextField(frame: NSRect(x: 95, y: 12, width: 80, height: 24))
        sizeField.stringValue = String(format: "%.0f", messageFontSize)
        sizeField.placeholderString = "100"
        accessory.addSubview(sizeField)
        
        // Idle Screen settings box
        let idleScreenSettingsBox = NSAlert()
        idleScreenSettingsBox.messageText = "Idle Screen Settings"
        idleScreenSettingsBox.accessoryView = accessory
        idleScreenSettingsBox.addButton(withTitle: "Save")
        idleScreenSettingsBox.addButton(withTitle: "Cancel")
        idleScreenSettingsBox.addButton(withTitle: "Reset to Default")
        
        // Toggable button for timer
        let timerButton = idleScreenSettingsBox.addButton(withTitle: showTime ? "Hide Time" : "Show Time")
        let toggleHandler = ToggleButtonHandler(initialState: showTime)
        idleScreenSettingsBox.layout()
        timerButton.target = toggleHandler
        timerButton.action = #selector(ToggleButtonHandler.toggleTimer(_:))
        
        idleScreenSettingsBox.window.initialFirstResponder = textView
        
        switch idleScreenSettingsBox.runModal() {
        case .alertFirstButtonReturn:   // Save
            let newMessage = textView.string.trimmingCharacters(in: .newlines)
            let newSize = CGFloat(sizeField.doubleValue)
            message  = newMessage.isEmpty ? "" : newMessage
            messageFontSize = newSize > 0 ? newSize : 100
            showTime = toggleHandler.isTimerOn
            NotificationCenter.default.post(name: .idleScreenSettingsDidChange, object: nil)
            
        case .alertThirdButtonReturn:   // Reset to Default
            message  = "We will start shortly.\nPlease stand by."
            messageFontSize = 100
            showTime = false
            NotificationCenter.default.post(name: .idleScreenSettingsDidChange, object: nil)
            
        default:   // Cancel
            break
        }
    }
}

class IdleScreen: NSObject {
    
    public static func renderIdleScreenContents(for size: NSSize) -> NSImage {
        let message = IdleScreenSettings.shared.message
        let fontSize = IdleScreenSettings.shared.messageFontSize
        let showTime = IdleScreenSettings.shared.showTime
        
        let idleScreenContents = NSImage(size: size)
        idleScreenContents.lockFocus()
        
        let hPad: CGFloat = 48
        let maxWidth = max(size.width - hPad * 2, 1)
        
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byWordWrapping
        
        let messageAttributes = NSAttributedString(string: message, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: centered
            ])
        
        let messageBounds = messageAttributes.boundingRect(
            with: NSSize(width: maxWidth, height: size.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        
        if showTime {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "hh:mm:ss a"
            let timerString = timeFormatter.string(from: Date())
            let timerFontSize = max(fontSize * 0.65, 24)
            
            let timeAttributes = NSAttributedString(string: timerString, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: timerFontSize, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.75),
                .paragraphStyle: centered
                ])
            
            let timeBounds = timeAttributes.boundingRect(
                with: NSSize(width: maxWidth, height: size.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            
            let gap = fontSize * 0.2
            let totalHeight = messageBounds.height + gap + timeBounds.height
            let blockStartY = (size.height - totalHeight) / 2
            
            let messageArea = NSRect(
                x: (size.width - messageBounds.width) / 2,
                y: blockStartY + timeBounds.height + gap,
                width:  messageBounds.width,
                height: messageBounds.height
            )
            
            let timeArea = NSRect(
                x: (size.width - timeBounds.width) / 2,
                y: blockStartY,
                width:  timeBounds.width,
                height: timeBounds.height
            )
            
            messageAttributes.draw(with: messageArea, options: [.usesLineFragmentOrigin, .usesFontLeading])
            timeAttributes.draw(with: timeArea, options: [.usesLineFragmentOrigin, .usesFontLeading])
        } else {
            let messageOnly = NSRect(
                x: (size.width  - messageBounds.width) / 2,
                y: (size.height - messageBounds.height) / 2,
                width:  messageBounds.width,
                height: messageBounds.height
            )
            
            messageAttributes.draw(with: messageOnly, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        
        idleScreenContents.unlockFocus()
        return idleScreenContents
    }
}

extension Notification.Name {
    static let idleScreenSettingsDidChange = Notification.Name("idleScreenSettingsDidChange")
}

private class ToggleButtonHandler: NSObject {
    
    private(set) var isTimerOn: Bool
    
    init(initialState: Bool) { self.isTimerOn = initialState }
    
    @objc func toggleTimer(_ sender: NSButton) {
        isTimerOn.toggle()
        sender.title = isTimerOn ? "Hide Time" : "Show Time"
    }
}
