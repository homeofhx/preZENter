import Cocoa

class MenuBarShortcuts: NSObject {
    
    public var toggleMenuItem: NSMenuItem?
    public var windowSubMenu = NSMenu()
    public var deviceSubMenu = NSMenu()
    
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
    
    public func updateMenuBarTime(with timeString: String) {
        DispatchQueue.main.async {
            self.menuBarItem.button?.title = "  " + timeString
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        let appDelegate = AppDelegate.sharedPlaceholder
        
        let timerButton = NSMenuItem(title: "Start Timer", action: #selector(AppDelegate.menuBarTimerHandler), keyEquivalent: "")
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
        
        let refreshItem = NSMenuItem(title: "Refresh Lists", action: #selector(AppDelegate.refresh), keyEquivalent: "")
        refreshItem.target = appDelegate
        menu.addItem(refreshItem)
                
        menuBarItem.menu = menu
    }
    
}
