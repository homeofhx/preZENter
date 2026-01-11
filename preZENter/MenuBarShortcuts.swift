import Cocoa

class MenuBarShortcuts: NSObject {
    
    public var toggleMenuItem: NSMenuItem?
    public var windowSubMenu = NSMenu()
    public var deviceSubMenu = NSMenu()
    public var screenSubMenu = NSMenu()
    
    internal private(set) var menuBarItem: NSStatusItem!
    
    override init() {
        super.init()
        
        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = menuBarItem.button {
            let icon = NSImage(named: NSImage.Name("MenuBarIcon"))
            icon?.isTemplate = true
            icon?.size = NSSize(width: 60, height: 18)
            button.image = icon
            button.title = "  00:00:00"
            button.imagePosition = .imageLeft
        }
        
        setupMenu()
    }
    
    public func updateMenuBarTimer(with timeString: String) {
        DispatchQueue.main.async {
            self.menuBarItem.button?.title = "  " + timeString
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        let appDelegate = AppDelegate.sharedPlaceholder
        
        let timerButton = NSMenuItem(title: "Start Timer", action: #selector(AppDelegate.menuBarPresenterTimerHandler), keyEquivalent: "")
        timerButton.target = appDelegate
        menu.addItem(timerButton)
        self.toggleMenuItem = timerButton
        
        menu.addItem(NSMenuItem.separator())
        
        let windowItem = NSMenuItem(title: "Application Windows", action: nil, keyEquivalent: "")
        windowItem.submenu = windowSubMenu
        menu.addItem(windowItem)
        
        let deviceItem = NSMenuItem(title: "Video Capture Devices", action: nil, keyEquivalent: "")
        deviceItem.submenu = deviceSubMenu
        menu.addItem(deviceItem)
        
        let screenItem = NSMenuItem(title: "Present On...", action: nil, keyEquivalent: "")
        screenItem.submenu = screenSubMenu
        menu.addItem(screenItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Contents", action: #selector(AppDelegate.refreshContents), keyEquivalent: "")
        refreshItem.target = appDelegate
        menu.addItem(refreshItem)
        
        menuBarItem.menu = menu
    }
    
}
