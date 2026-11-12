import Cocoa

final class SettingsWindowController: NSWindowController {

    private let tabViewController = SettingsTabViewController()

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 410),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "preZENter Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)

        tabViewController.tabStyle = .toolbar
        addTab(GeneralSettingsViewController(), title: "General", image: NSImage(named: NSImage.preferencesGeneralName))
        addTab(PresentingSettingsViewController(), title: "Presenting", image: NSImage(named: NSImage.advancedName))
        addTab(IdleScreenSettingsViewController(), title: "Idle Screen", image: NSImage(named: NSImage.fontPanelName))
        window.contentViewController = tabViewController
        tabViewController.onSelectionDidChange = { [weak self] in
            self?.resizeForSelectedTab(animated: self?.window?.isVisible == true)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        resizeForSelectedTab(animated: false)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func addTab(_ viewController: NSViewController, title: String, image: NSImage?) {
        viewController.title = title
        let tabItem = NSTabViewItem(viewController: viewController)
        tabItem.label = title
        tabItem.image = image
        tabViewController.addTabViewItem(tabItem)
    }

    private func resizeForSelectedTab(animated: Bool) {
        guard let window = window,
              tabViewController.tabViewItems.indices.contains(tabViewController.selectedTabViewItemIndex),
              let selectedController = tabViewController
                .tabViewItems[tabViewController.selectedTabViewItemIndex].viewController else { return }

        _ = selectedController.view
        selectedController.view.layoutSubtreeIfNeeded()
        let targetSize = selectedController.preferredContentSize
        guard targetSize.width > 0, targetSize.height > 0 else { return }

        let currentLayoutSize = window.contentLayoutRect.size
        let widthChange = targetSize.width - currentLayoutSize.width
        let heightChange = targetSize.height - currentLayoutSize.height
        guard abs(widthChange) > 0.5 || abs(heightChange) > 0.5 else { return }

        var targetFrame = window.frame
        targetFrame.origin.x -= widthChange / 2
        targetFrame.origin.y -= heightChange
        targetFrame.size.width += widthChange
        targetFrame.size.height += heightChange
        window.setFrame(targetFrame, display: true, animate: animated)
    }

}

private final class SettingsTabViewController: NSTabViewController {

    var onSelectionDidChange: (() -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelectionDidChange?()
    }

}

private final class GeneralSettingsViewController: NSViewController {

    private let keepAwakeButton = settingsCheckbox(title: "Keep this Mac awake when preZENter is running")
    private let promptForDisplayButton = settingsCheckbox(title: "Prompt me to move Live Window when an external display is connected")

    override func loadView() {
        view = settingsContentView()
        let stack = settingsStack(in: view)

        keepAwakeButton.target = self
        keepAwakeButton.action = #selector(keepAwakeChanged(_:))
        stack.addArrangedSubview(keepAwakeButton)

        promptForDisplayButton.target = self
        promptForDisplayButton.action = #selector(promptForDisplayChanged(_:))
        stack.addArrangedSubview(promptForDisplayButton)
        finalizeSettingsLayout(for: self, stack: stack)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        keepAwakeButton.state = ApplicationSettings.shared.keepsMacAwake ? .on : .off
        promptForDisplayButton.state = ApplicationSettings.shared.promptsForExternalDisplay ? .on : .off
    }

    @objc private func keepAwakeChanged(_ sender: NSButton) {
        ApplicationSettings.shared.keepsMacAwake = sender.state == .on
    }

    @objc private func promptForDisplayChanged(_ sender: NSButton) {
        ApplicationSettings.shared.promptsForExternalDisplay = sender.state == .on
    }

}

private final class PresentingSettingsViewController: NSViewController, NSTextFieldDelegate {

    private let forceCoreGraphicsButton = settingsCheckbox(title: "Force using Core Graphics for capturing application windows and screens")
    private let availabilityDescription = settingsDescription("")
    private let frameRateField = NSTextField(string: "")
    private let resetFrameRateButton = NSButton(title: "Reset to Default", target: nil, action: nil)
    private let hideCursorButton = settingsCheckbox(title: "Hide mouse cursor when capturing application windows and screens")
    private let bringWindowToFrontButton = settingsCheckbox(title: "Bring the selected application's window to the front of all application windows")

    override func loadView() {
        view = settingsContentView()
        let stack = settingsStack(in: view)

        forceCoreGraphicsButton.target = self
        forceCoreGraphicsButton.action = #selector(forceCoreGraphicsChanged(_:))
        stack.addArrangedSubview(forceCoreGraphicsButton)
        stack.addArrangedSubview(availabilityDescription)

        let frameRateRow = NSStackView()
        frameRateRow.orientation = .horizontal
        frameRateRow.alignment = .centerY
        frameRateRow.spacing = 8
        frameRateRow.addArrangedSubview(NSTextField(labelWithString: "Core Graphics capturer frame rate (FPS):"))

        frameRateField.alignment = .right
        frameRateField.delegate = self
        frameRateField.toolTip = "Enter an integer between 1 and 240"
        frameRateField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        frameRateRow.addArrangedSubview(frameRateField)

        resetFrameRateButton.target = self
        resetFrameRateButton.action = #selector(resetFrameRate(_:))
        frameRateRow.addArrangedSubview(resetFrameRateButton)
        stack.addArrangedSubview(frameRateRow)

        hideCursorButton.target = self
        hideCursorButton.action = #selector(hideCursorChanged(_:))
        stack.addArrangedSubview(hideCursorButton)
        stack.addArrangedSubview(settingsDescription("Hiding the mouse cursor could improve capture performance when using the Core Graphics capturer."))

        bringWindowToFrontButton.target = self
        bringWindowToFrontButton.action = #selector(bringWindowToFrontChanged(_:))
        stack.addArrangedSubview(bringWindowToFrontButton)

        updateAvailability()
        finalizeSettingsLayout(for: self, stack: stack)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadValues()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === frameRateField,
              let editor = frameRateField.currentEditor() as? NSTextView else { return }

        let original = editor.string
        let selection = editor.selectedRange()
        let prefixEnd = original.index(original.startIndex, offsetBy: min(selection.location, original.count))
        let prefix = String(original[..<prefixEnd])
        let filtered = original.filter { $0 >= "0" && $0 <= "9" }
        guard filtered != original else { return }

        editor.string = filtered
        let cursorPosition = prefix.filter { $0 >= "0" && $0 <= "9" }.count
        editor.setSelectedRange(NSRange(location: cursorPosition, length: 0))
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === frameRateField else { return }
        commitFrameRate()
    }

    @objc private func forceCoreGraphicsChanged(_ sender: NSButton) {
        guard #available(macOS 12.3, *) else { return }
        ApplicationSettings.shared.forcesCoreGraphicsCapture = sender.state == .on
        updateFrameRateAvailability()
    }

    @objc private func resetFrameRate(_ sender: Any) {
        ApplicationSettings.shared.coreGraphicsFrameRate = ApplicationSettings.Defaults.coreGraphicsFrameRate
        frameRateField.integerValue = ApplicationSettings.Defaults.coreGraphicsFrameRate
    }

    @objc private func hideCursorChanged(_ sender: NSButton) {
        ApplicationSettings.shared.hidesCapturedMouseCursor = sender.state == .on
    }

    @objc private func bringWindowToFrontChanged(_ sender: NSButton) {
        ApplicationSettings.shared.bringsSelectedApplicationWindowToFront = sender.state == .on
    }

    private func reloadValues() {
        updateAvailability()
        frameRateField.integerValue = ApplicationSettings.shared.coreGraphicsFrameRate
        hideCursorButton.state = ApplicationSettings.shared.hidesCapturedMouseCursor ? .on : .off
        bringWindowToFrontButton.state = ApplicationSettings.shared.bringsSelectedApplicationWindowToFront ? .on : .off
    }

    private func updateAvailability() {
        if #available(macOS 12.3, *) {
            forceCoreGraphicsButton.isEnabled = true
            forceCoreGraphicsButton.state = ApplicationSettings.shared.forcesCoreGraphicsCapture ? .on : .off
            availabilityDescription.stringValue = "When off, macOS 12.3 or later uses ScreenCaptureKit capturer by default, and can fall back to Core Graphics capturer if needed."
        } else {
            forceCoreGraphicsButton.isEnabled = false
            forceCoreGraphicsButton.state = .on
            availabilityDescription.stringValue = "ScreenCaptureKit capturer requires macOS 12.3 or later. Core Graphics capturer is already in use on this Mac."
        }
        updateFrameRateAvailability()
    }

    private func updateFrameRateAvailability() {
        let isCoreGraphicsSelected = forceCoreGraphicsButton.state == .on
        frameRateField.isEnabled = isCoreGraphicsSelected
        resetFrameRateButton.isEnabled = isCoreGraphicsSelected
    }

    private func commitFrameRate() {
        let enteredValue = Int(frameRateField.stringValue) ?? ApplicationSettings.Defaults.coreGraphicsFrameRate
        ApplicationSettings.shared.coreGraphicsFrameRate = enteredValue
        frameRateField.integerValue = ApplicationSettings.shared.coreGraphicsFrameRate
    }

}

private final class IdleScreenSettingsViewController: NSViewController {

    private let messageTextView = NSTextView()
    private let fontSizeField = NSTextField(string: "")
    private let showTimeButton = settingsCheckbox(title: "Show the current time")

    override func loadView() {
        view = settingsContentView()
        let stack = settingsStack(in: view)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 576).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 155).isActive = true

        messageTextView.isEditable = true
        messageTextView.isRichText = false
        messageTextView.isAutomaticQuoteSubstitutionEnabled = false
        messageTextView.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageTextView.frame = NSRect(x: 0, y: 0, width: 576, height: 155)
        messageTextView.minSize = NSSize(width: 0, height: 155)
        messageTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        messageTextView.isVerticallyResizable = true
        messageTextView.autoresizingMask = [.width]
        messageTextView.textContainer?.widthTracksTextView = true
        scrollView.documentView = messageTextView
        stack.addArrangedSubview(scrollView)

        let optionsRow = NSStackView()
        optionsRow.orientation = .horizontal
        optionsRow.alignment = .centerY
        optionsRow.spacing = 8
        optionsRow.addArrangedSubview(NSTextField(labelWithString: "Font size (pt):"))

        let fontSizeFormatter = NumberFormatter()
        fontSizeFormatter.allowsFloats = false
        fontSizeFormatter.minimum = 1
        fontSizeFormatter.maximum = 500
        fontSizeField.formatter = fontSizeFormatter
        fontSizeField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        optionsRow.addArrangedSubview(fontSizeField)
        optionsRow.addArrangedSubview(showTimeButton)
        stack.addArrangedSubview(optionsRow)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(NSButton(title: "Save Idle Screen Settings", target: self, action: #selector(saveSettings(_:))))
        buttonRow.addArrangedSubview(NSButton(title: "Reset to Default", target: self, action: #selector(resetSettings(_:))))
        stack.addArrangedSubview(buttonRow)
        finalizeSettingsLayout(for: self, stack: stack)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadValues()
    }

    @objc private func saveSettings(_ sender: Any) {
        let fontSize = CGFloat(fontSizeField.doubleValue)
        IdleScreenSettings.shared.update(message: messageTextView.string, fontSize: fontSize, showTime: showTimeButton.state == .on)
        reloadValues()
    }

    @objc private func resetSettings(_ sender: Any) {
        IdleScreenSettings.shared.resetToDefaults()
        reloadValues()
    }

    private func reloadValues() {
        let settings = IdleScreenSettings.shared
        messageTextView.string = settings.message
        fontSizeField.stringValue = String(format: "%.0f", settings.messageFontSize)
        showTimeButton.state = settings.showTime ? .on : .off
    }

}

private func settingsContentView() -> NSView {
    return NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 1))
}

private func settingsStack(in container: NSView) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                                 stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
                                 stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 26)])
    return stack
}

private func finalizeSettingsLayout(for viewController: NSViewController, stack: NSStackView) {
    viewController.view.layoutSubtreeIfNeeded()
    let contentHeight = ceil(stack.fittingSize.height) + 52
    let size = NSSize(width: 640, height: contentHeight)
    viewController.preferredContentSize = size
    viewController.view.frame.size = size
}

private func settingsCheckbox(title: String) -> NSButton {
    let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
    button.cell?.wraps = true
    button.widthAnchor.constraint(lessThanOrEqualToConstant: 576).isActive = true
    return button
}

private func settingsDescription(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.maximumNumberOfLines = 0
    label.preferredMaxLayoutWidth = 560
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 560).isActive = true
    return label
}
