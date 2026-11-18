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
        addTab(CustomizationSettingsViewController(), title: "Customization", image: NSImage(named: NSImage.fontPanelName))
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
    private let automaticallyMoveButton = settingsCheckbox(title: "Automatically move Live Window to the newly connected display")

    override func loadView() {
        view = settingsContentView()
        let stack = settingsStack(in: view)

        keepAwakeButton.target = self
        keepAwakeButton.action = #selector(keepAwakeChanged(_:))
        stack.addArrangedSubview(keepAwakeButton)

        promptForDisplayButton.target = self
        promptForDisplayButton.action = #selector(promptForDisplayChanged(_:))
        stack.addArrangedSubview(promptForDisplayButton)

        automaticallyMoveButton.target = self
        automaticallyMoveButton.action = #selector(automaticallyMoveChanged(_:))
        stack.addArrangedSubview(automaticallyMoveButton)
        finalizeSettingsLayout(for: self, stack: stack)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        keepAwakeButton.state = ApplicationSettings.shared.keepsMacAwake ? .on : .off
        promptForDisplayButton.state = ApplicationSettings.shared.promptsForExternalDisplay ? .on : .off
        automaticallyMoveButton.state = ApplicationSettings.shared.automaticallyMovesLiveWindow ? .on : .off
    }

    @objc private func keepAwakeChanged(_ sender: NSButton) {
        ApplicationSettings.shared.keepsMacAwake = sender.state == .on
    }

    @objc private func promptForDisplayChanged(_ sender: NSButton) {
        ApplicationSettings.shared.promptsForExternalDisplay = sender.state == .on
        reloadDisplayChoice()
    }

    @objc private func automaticallyMoveChanged(_ sender: NSButton) {
        ApplicationSettings.shared.automaticallyMovesLiveWindow = sender.state == .on
        reloadDisplayChoice()
    }

    private func reloadDisplayChoice() {
        promptForDisplayButton.state = ApplicationSettings.shared.promptsForExternalDisplay ? .on : .off
        automaticallyMoveButton.state = ApplicationSettings.shared.automaticallyMovesLiveWindow ? .on : .off
    }

}

private final class PresentingSettingsViewController: NSViewController, NSTextFieldDelegate {

    private let forceCoreGraphicsButton = settingsCheckbox(title: "Force using Core Graphics for capturing application windows and screens")
    private let availabilityDescription = settingsDescription("")
    private let frameRateField = NSTextField(string: "")
    private let resetFrameRateButton = NSButton(title: "Reset to Default", target: nil, action: nil)
    private let hideCursorButton = settingsCheckbox(title: "Hide mouse cursor when capturing application windows and screens")
    private let bringWindowToFrontButton = settingsCheckbox(title: "Bring the selected application's window to the front of all application windows")
    private let fadeBetweenContentsButton = settingsCheckbox(title: "Fade to black for")
    private let transitionDurationField = NSTextField(string: "")
    private let resetTransitionButton = NSButton(title: "Reset to Default", target: nil, action: nil)
    private let outputVolumeSlider = NSSlider()
    private let outputVolumeLabel = NSTextField(labelWithString: "100%")
    private let muteVideoDeviceButton = settingsCheckbox(title: "video capture devices")
    private let muteIOSDeviceButton = settingsCheckbox(title: "iOS devices")
    private let monoAudioButton = settingsCheckbox(title: "Mono audio output")

    override func loadView() {
        view = settingsContentView()
        let stack = settingsStack(in: view)

        stack.addArrangedSubview(settingsSectionTitle("Video"))

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

        let transitionRow = NSStackView()
        transitionRow.orientation = .horizontal
        transitionRow.alignment = .centerY
        transitionRow.spacing = 8
        fadeBetweenContentsButton.target = self
        fadeBetweenContentsButton.action = #selector(fadeBetweenContentsChanged(_:))
        transitionRow.addArrangedSubview(fadeBetweenContentsButton)
        transitionDurationField.alignment = .right
        transitionDurationField.delegate = self
        transitionDurationField.toolTip = "Enter a duration between 0 and 10 seconds"
        transitionDurationField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        transitionRow.addArrangedSubview(transitionDurationField)
        transitionRow.addArrangedSubview(NSTextField(labelWithString: "seconds when switching between contents"))
        resetTransitionButton.target = self
        resetTransitionButton.action = #selector(resetTransition(_:))
        transitionRow.addArrangedSubview(resetTransitionButton)
        stack.addArrangedSubview(transitionRow)

        stack.addArrangedSubview(settingsSeparator())
        stack.addArrangedSubview(settingsSectionTitle("Audio"))

        let volumeRow = NSStackView()
        volumeRow.orientation = .horizontal
        volumeRow.alignment = .centerY
        volumeRow.spacing = 8
        volumeRow.addArrangedSubview(NSTextField(labelWithString: "Output volume:"))
        outputVolumeSlider.minValue = 0
        outputVolumeSlider.maxValue = 100
        outputVolumeSlider.isContinuous = true
        outputVolumeSlider.target = self
        outputVolumeSlider.action = #selector(outputVolumeChanged(_:))
        outputVolumeSlider.widthAnchor.constraint(equalToConstant: 280).isActive = true
        volumeRow.addArrangedSubview(outputVolumeSlider)
        outputVolumeLabel.alignment = .right
        outputVolumeLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true
        volumeRow.addArrangedSubview(outputVolumeLabel)
        stack.addArrangedSubview(volumeRow)

        let muteRow = NSStackView()
        muteRow.orientation = .horizontal
        muteRow.alignment = .centerY
        muteRow.spacing = 8
        muteRow.addArrangedSubview(NSTextField(labelWithString: "Mute audio from:"))
        muteVideoDeviceButton.target = self
        muteVideoDeviceButton.action = #selector(muteVideoDeviceChanged(_:))
        muteRow.addArrangedSubview(muteVideoDeviceButton)
        muteIOSDeviceButton.target = self
        muteIOSDeviceButton.action = #selector(muteIOSDeviceChanged(_:))
        muteRow.addArrangedSubview(muteIOSDeviceButton)
        stack.addArrangedSubview(muteRow)

        monoAudioButton.target = self
        monoAudioButton.action = #selector(monoAudioChanged(_:))
        stack.addArrangedSubview(monoAudioButton)

        updateAvailability()
        finalizeSettingsLayout(for: self, stack: stack)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadValues()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === frameRateField {
            filterNumericInput(in: frameRateField, allowsDecimalSeparator: false)
        } else if field === transitionDurationField {
            filterNumericInput(in: transitionDurationField, allowsDecimalSeparator: true)
            if let duration = Double(transitionDurationField.stringValue), duration >= 0 {
                ApplicationSettings.shared.transitionDuration = duration
            }
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === frameRateField {
            commitFrameRate()
        } else if field === transitionDurationField {
            commitTransitionDuration()
        }
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

    @objc private func fadeBetweenContentsChanged(_ sender: NSButton) {
        ApplicationSettings.shared.fadesBetweenContents = sender.state == .on
        updateTransitionAvailability()
    }

    @objc private func resetTransition(_ sender: Any) {
        ApplicationSettings.shared.transitionDuration = ApplicationSettings.Defaults.transitionDuration
        transitionDurationField.stringValue = formattedDuration(ApplicationSettings.Defaults.transitionDuration)
    }

    @objc private func outputVolumeChanged(_ sender: NSSlider) {
        let volume = Int(sender.doubleValue.rounded())
        ApplicationSettings.shared.outputVolume = volume
        outputVolumeLabel.stringValue = "\(volume)%"
    }

    @objc private func muteVideoDeviceChanged(_ sender: NSButton) {
        ApplicationSettings.shared.mutesVideoDeviceAudio = sender.state == .on
    }

    @objc private func muteIOSDeviceChanged(_ sender: NSButton) {
        ApplicationSettings.shared.mutesIOSDeviceAudio = sender.state == .on
    }

    @objc private func monoAudioChanged(_ sender: NSButton) {
        ApplicationSettings.shared.usesMonoAudioOutput = sender.state == .on
    }

    private func reloadValues() {
        updateAvailability()
        frameRateField.integerValue = ApplicationSettings.shared.coreGraphicsFrameRate
        hideCursorButton.state = ApplicationSettings.shared.hidesCapturedMouseCursor ? .on : .off
        bringWindowToFrontButton.state = ApplicationSettings.shared.bringsSelectedApplicationWindowToFront ? .on : .off
        fadeBetweenContentsButton.state = ApplicationSettings.shared.fadesBetweenContents ? .on : .off
        transitionDurationField.stringValue = formattedDuration(ApplicationSettings.shared.transitionDuration)
        outputVolumeSlider.integerValue = ApplicationSettings.shared.outputVolume
        outputVolumeLabel.stringValue = "\(ApplicationSettings.shared.outputVolume)%"
        muteVideoDeviceButton.state = ApplicationSettings.shared.mutesVideoDeviceAudio ? .on : .off
        muteIOSDeviceButton.state = ApplicationSettings.shared.mutesIOSDeviceAudio ? .on : .off
        monoAudioButton.state = ApplicationSettings.shared.usesMonoAudioOutput ? .on : .off
        updateTransitionAvailability()
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

    private func commitTransitionDuration() {
        let duration = Double(transitionDurationField.stringValue) ?? ApplicationSettings.Defaults.transitionDuration
        ApplicationSettings.shared.transitionDuration = duration
        transitionDurationField.stringValue = formattedDuration(ApplicationSettings.shared.transitionDuration)
    }

    private func updateTransitionAvailability() {
        let isEnabled = fadeBetweenContentsButton.state == .on
        transitionDurationField.isEnabled = isEnabled
        resetTransitionButton.isEnabled = isEnabled
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        return String(format: "%g", duration)
    }

}

private final class CustomizationSettingsViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {

    private let messageTextView = NSTextView()
    private let fontSizeField = NSTextField(string: "")
    private let showTimeButton = settingsCheckbox(title: "Show the current time")
    private let showSourceNameButton = settingsCheckbox(title: "Display the currently presented source's name on Live Window")
    private let showCustomTextButton = settingsCheckbox(title: "Customized text:")
    private let customTextField = NSTextField(string: "")
    private let positionPopup = NSPopUpButton()
    private let liveWindowTextSizeField = NSTextField(string: "")

    override func loadView() {
        view = settingsContentView()
        let stack = settingsStack(in: view)

        stack.addArrangedSubview(settingsSectionTitle("Idle Screen Text"))

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 576).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 100).isActive = true

        messageTextView.isEditable = true
        messageTextView.isRichText = false
        messageTextView.isAutomaticQuoteSubstitutionEnabled = false
        messageTextView.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageTextView.frame = NSRect(x: 0, y: 0, width: 576, height: 100)
        messageTextView.minSize = NSSize(width: 0, height: 100)
        messageTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        messageTextView.isVerticallyResizable = true
        messageTextView.autoresizingMask = [.width]
        messageTextView.textContainer?.widthTracksTextView = true
        messageTextView.delegate = self
        scrollView.documentView = messageTextView
        stack.addArrangedSubview(scrollView)

        let optionsRow = NSStackView()
        optionsRow.orientation = .horizontal
        optionsRow.alignment = .centerY
        optionsRow.spacing = 8
        optionsRow.addArrangedSubview(NSTextField(labelWithString: "Text size (pt):"))

        let fontSizeFormatter = NumberFormatter()
        fontSizeFormatter.allowsFloats = false
        fontSizeFormatter.minimum = 1
        fontSizeFormatter.maximum = 500
        fontSizeField.formatter = fontSizeFormatter
        fontSizeField.delegate = self
        fontSizeField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        optionsRow.addArrangedSubview(fontSizeField)
        showTimeButton.target = self
        showTimeButton.action = #selector(showTimeChanged(_:))
        optionsRow.addArrangedSubview(showTimeButton)
        optionsRow.addArrangedSubview(NSButton(title: "Reset to Default", target: self, action: #selector(resetIdleScreenSettings(_:))))
        stack.addArrangedSubview(optionsRow)

        stack.addArrangedSubview(settingsSeparator())
        stack.addArrangedSubview(settingsSectionTitle("Text on Live Window"))

        showSourceNameButton.target = self
        showSourceNameButton.action = #selector(showSourceNameChanged(_:))
        stack.addArrangedSubview(showSourceNameButton)

        let customTextRow = NSStackView()
        customTextRow.orientation = .horizontal
        customTextRow.alignment = .centerY
        customTextRow.spacing = 8
        showCustomTextButton.target = self
        showCustomTextButton.action = #selector(showCustomTextChanged(_:))
        customTextRow.addArrangedSubview(showCustomTextButton)
        customTextField.delegate = self
        customTextField.placeholderString = "Text to display"
        customTextField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        customTextRow.addArrangedSubview(customTextField)
        stack.addArrangedSubview(customTextRow)

        let liveWindowTextOptionsRow = NSStackView()
        liveWindowTextOptionsRow.orientation = .horizontal
        liveWindowTextOptionsRow.alignment = .centerY
        liveWindowTextOptionsRow.spacing = 8
        liveWindowTextOptionsRow.addArrangedSubview(NSTextField(labelWithString: "Position:"))
        positionPopup.addItems(withTitles: LiveWindowTextPosition.all.map { $0.title })
        positionPopup.target = self
        positionPopup.action = #selector(positionChanged(_:))
        liveWindowTextOptionsRow.addArrangedSubview(positionPopup)
        liveWindowTextOptionsRow.addArrangedSubview(NSTextField(labelWithString: "Text size (pt):"))
        liveWindowTextSizeField.delegate = self
        liveWindowTextSizeField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        liveWindowTextOptionsRow.addArrangedSubview(liveWindowTextSizeField)
        liveWindowTextOptionsRow.addArrangedSubview(NSButton(title: "Reset to Default", target: self, action: #selector(resetLiveWindowTextAppearance(_:))))
        stack.addArrangedSubview(liveWindowTextOptionsRow)
        finalizeSettingsLayout(for: self, stack: stack)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadValues()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === messageTextView else { return }
        IdleScreenSettings.shared.updateMessage(messageTextView.string)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === fontSizeField {
            filterNumericInput(in: field, allowsDecimalSeparator: false)
            if let size = Double(field.stringValue), size > 0 {
                IdleScreenSettings.shared.updateFontSize(CGFloat(size))
            }
        } else if field === liveWindowTextSizeField {
            filterNumericInput(in: field, allowsDecimalSeparator: false)
            if let size = Double(field.stringValue), size > 0 {
                LiveWindowTextSettings.shared.updateFontSize(CGFloat(size))
            }
        } else if field === customTextField {
            LiveWindowTextSettings.shared.updateCustomText(field.stringValue)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === fontSizeField {
            field.stringValue = String(format: "%.0f", IdleScreenSettings.shared.messageFontSize)
        } else if field === liveWindowTextSizeField {
            field.stringValue = String(format: "%.0f", LiveWindowTextSettings.shared.fontSize)
        }
    }

    @objc private func showTimeChanged(_ sender: NSButton) {
        IdleScreenSettings.shared.updateShowTime(sender.state == .on)
    }

    @objc private func resetIdleScreenSettings(_ sender: Any) {
        IdleScreenSettings.shared.resetToDefaults()
        reloadIdleScreenValues()
    }

    @objc private func showSourceNameChanged(_ sender: NSButton) {
        LiveWindowTextSettings.shared.updateShowsPresentedSourceName(sender.state == .on)
        reloadLiveWindowTextMode()
    }

    @objc private func showCustomTextChanged(_ sender: NSButton) {
        LiveWindowTextSettings.shared.updateShowsCustomText(sender.state == .on)
        reloadLiveWindowTextMode()
    }

    @objc private func positionChanged(_ sender: NSPopUpButton) {
        guard LiveWindowTextPosition.all.indices.contains(sender.indexOfSelectedItem) else { return }
        LiveWindowTextSettings.shared.updatePosition(LiveWindowTextPosition.all[sender.indexOfSelectedItem])
    }

    @objc private func resetLiveWindowTextAppearance(_ sender: Any) {
        LiveWindowTextSettings.shared.resetTextAppearance()
        reloadLiveWindowTextAppearance()
    }

    private func reloadValues() {
        reloadIdleScreenValues()
        let liveSettings = LiveWindowTextSettings.shared
        customTextField.stringValue = liveSettings.customText
        reloadLiveWindowTextMode()
        reloadLiveWindowTextAppearance()
    }

    private func reloadIdleScreenValues() {
        let settings = IdleScreenSettings.shared
        messageTextView.string = settings.message
        fontSizeField.stringValue = String(format: "%.0f", settings.messageFontSize)
        showTimeButton.state = settings.showTime ? .on : .off
    }

    private func reloadLiveWindowTextMode() {
        let settings = LiveWindowTextSettings.shared
        showSourceNameButton.state = settings.showsPresentedSourceName ? .on : .off
        showCustomTextButton.state = settings.showsCustomText ? .on : .off
        customTextField.isEnabled = settings.showsCustomText
    }

    private func reloadLiveWindowTextAppearance() {
        let settings = LiveWindowTextSettings.shared
        positionPopup.selectItem(at: LiveWindowTextPosition.all.firstIndex(of: settings.position) ?? 3)
        liveWindowTextSizeField.stringValue = String(format: "%.0f", settings.fontSize)
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

private func settingsSectionTitle(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 14, weight: .semibold)
    return label
}

private func settingsSeparator() -> NSBox {
    let separator = NSBox()
    separator.boxType = .separator
    separator.widthAnchor.constraint(equalToConstant: 576).isActive = true
    return separator
}

private func filterNumericInput(in field: NSTextField, allowsDecimalSeparator: Bool) {
    guard let editor = field.currentEditor() as? NSTextView else { return }
    let original = editor.string
    let selection = editor.selectedRange()
    let prefixEnd = original.index(original.startIndex, offsetBy: min(selection.location, original.count))
    let prefix = String(original[..<prefixEnd])

    func filteredValue(_ value: String) -> String {
        var foundDecimalSeparator = false
        return String(value.filter { character in
            if character >= "0" && character <= "9" { return true }
            if allowsDecimalSeparator && character == "." && !foundDecimalSeparator {
                foundDecimalSeparator = true
                return true
            }
            return false
        })
    }

    let filtered = filteredValue(original)
    guard filtered != original else { return }
    editor.string = filtered
    editor.setSelectedRange(NSRange(location: filteredValue(prefix).count, length: 0))
}
