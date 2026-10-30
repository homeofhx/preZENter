import Cocoa

class MenuBarShortcuts: NSObject {
    
    public var toggleMenuItem: NSMenuItem?
    public var windowSubMenu = NSMenu()
    public var deviceSubMenu = NSMenu()
    public var iOSDeviceSubMenu = NSMenu()
    public var screenSubMenu = NSMenu()
    public var displaySubMenu = NSMenu()
    public var audioOutputSubMenu = NSMenu()
    public var currentPresentedContentText: NSMenuItem?
    
    internal private(set) var menuBarItem: NSStatusItem!
    
    private var timerText = ""
    private var isPresenting = false
    
    override init() {
        super.init()
        
        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = menuBarItem.button {
            let icon = NSImage(named: NSImage.Name("MenuBarIcon"))
            icon?.isTemplate = true
            icon?.size = NSSize(width: 60, height: 18)
            button.image = icon
            button.imagePosition = .imageLeft
        }
        
        updateMenuBarTitle()
        setupMenu()
    }
    
    public func updateMenuBarTimer(with timeString: String) {
        DispatchQueue.main.async {
            self.timerText = timeString
            self.updateMenuBarTitle()
        }
    }
    
    public func updatePresentationStatus(isPresenting: Bool) {
        DispatchQueue.main.async {
            self.isPresenting = isPresenting
            self.updateMenuBarTitle()
            self.currentPresentedContentText?.image = self.presentationStatusIndicator()
        }
    }
    
    private func presentationStatusIndicator() -> NSImage? {
        return NSImage(named: isPresenting ? NSImage.statusAvailableName : NSImage.statusUnavailableName)
    }
    
    private func updateMenuBarTitle() {
        guard let button = menuBarItem.button else { return }
        let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
        let statusIcon = NSTextAttachment()
        statusIcon.image = presentationStatusIndicator()
        statusIcon.bounds = NSRect(x: 0, y: (font.capHeight - 16) / 2, width: 16, height: 16)
        let title = NSMutableAttributedString(string: " ")
        title.append(NSAttributedString(attachment: statusIcon))
        if !timerText.isEmpty { title.append(NSAttributedString(string: " " + timerText)) }
        title.addAttribute(.font, value: font, range: NSRange(location: 0, length: title.length))
        button.attributedTitle = title
    }
    
    public func updatePresentingIndicator(with contentName: String) {
        DispatchQueue.main.async {
            let contentText = contentName.isEmpty ? "Select something to present..." : "Presenting: \(contentName)"
            self.currentPresentedContentText?.title = contentText
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let presentingIndicator = NSMenuItem(title: "Select something to present...", action: nil, keyEquivalent: "")
        presentingIndicator.image = presentationStatusIndicator()
        presentingIndicator.isEnabled = false
        menu.addItem(presentingIndicator)
        self.currentPresentedContentText = presentingIndicator
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Contents", action: #selector(AppDelegate.refreshContents), keyEquivalent: "")
        refreshItem.target = nil
        menu.addItem(refreshItem)
        
        let timerButton = NSMenuItem(title: "Start Timer", action: #selector(AppDelegate.menuBarPresenterTimerHandler), keyEquivalent: "")
        timerButton.target = nil
        menu.addItem(timerButton)
        self.toggleMenuItem = timerButton
        
        menu.addItem(NSMenuItem.separator())
        
        let windowItem = NSMenuItem(title: "Application Windows", action: nil, keyEquivalent: "")
        windowItem.submenu = windowSubMenu
        menu.addItem(windowItem)
        
        let screenItem = NSMenuItem(title: "Screens", action: nil, keyEquivalent: "")
        screenItem.submenu = screenSubMenu
        menu.addItem(screenItem)
        
        let deviceItem = NSMenuItem(title: "Video Capture Devices", action: nil, keyEquivalent: "")
        deviceItem.submenu = deviceSubMenu
        menu.addItem(deviceItem)
        
        let iOSDeviceItem = NSMenuItem(title: "iOS Device", action: nil, keyEquivalent: "")
        iOSDeviceItem.submenu = iOSDeviceSubMenu
        menu.addItem(iOSDeviceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let displayItem = NSMenuItem(title: "Present On...", action: nil, keyEquivalent: "")
        displayItem.submenu = displaySubMenu
        menu.addItem(displayItem)
        
        let audioOutputItem = NSMenuItem(title: "Audio Output To...", action: nil, keyEquivalent: "")
        audioOutputItem.submenu = audioOutputSubMenu
        menu.addItem(audioOutputItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let stopPresentingItem = NSMenuItem(title: "Stop Presenting", action: #selector(AppDelegate.menuBarStopPresentingHandler), keyEquivalent: "")
        stopPresentingItem.target = nil
        menu.addItem(stopPresentingItem)
        
        menuBarItem.menu = menu
    }
    
}
