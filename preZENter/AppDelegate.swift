import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var windowsList: NSPopUpButton!
    @IBOutlet weak var devList: NSPopUpButton!
    @IBOutlet weak var liveContentIndicator: NSTextField!
    @IBOutlet weak var timerText: NSTextField!
    @IBOutlet weak var timerButtonLabel: NSTextField!
    
    public static var sharedPlaceholder: AppDelegate!
    
    private var liveWindow: LiveWindow?
    private var videoDevs = VideoCaptureDevs()
    private var windows = Windows()
    private let presenterTimer = PresenterTimer()
    private var isTimerRunning: Bool = false
    private var menuBarShortcuts = MenuBarShortcuts()
    private let screenSwitcher = ScreenSwitcher()
    
    @IBAction func getLatestRelease(_ sender: AnyObject) {
        let url = URL(string: "https://github.com/homeofhx/preZENter/releases/latest")
        NSWorkspace.shared.open(url!)
    }
    
    @IBAction func selectWindow(_ sender: Any) {
        setup(list: windowsList)
        videoDevs.stopVideoDevSession(liveWindow: liveWindow!)
        windows.selectWindow(popup: windowsList, liveWindow: liveWindow!)
    }
    
    @IBAction func selectVideoDev(_ sender: Any) {
        setup(list: devList)
        windows.stopWindowSession(liveWindow: liveWindow!)
        videoDevs.selectDev(popup: devList, liveWindow: liveWindow!)
    }
    
    @IBAction func refreshContents(_ sender: Any) {
        windows.refreshWindowsOnScreen(popup: windowsList)
        videoDevs.refreshDevs(popup: devList)
        refreshMenuBarItems()
    }
    
    @IBAction func presenterTimerButtonPressed(_ sender: Any) {
        startOrStopPresenterTimer()
    }
    
    @IBAction func showScreenList(_ sender: NSButton) {
        let screenList = NSMenu(title: "Select a Screen")
        refreshScreens(screenList)
        let point = NSPoint(x: 0, y: sender.frame.height)
        screenList.popUp(positioning: nil, at: point, in: sender)
    }
    
    @objc func switchLiveWindowScreen(_ sender: NSMenuItem) {
        if liveWindow == nil {
            setup(list: windowsList)
        }
        
        if let liveWinInstance = liveWindow?.window {
            screenSwitcher.moveLiveWindowToSelectedScreen(window: liveWinInstance, to: sender.tag)
        }
    }
    
    @objc func menuBarPresenterTimerHandler() {
        startOrStopPresenterTimer()
    }
    
    @objc func menuBarWindowsHandler(_ sender: NSMenuItem) {
        windowsList.selectItem(at: sender.tag)
        selectWindow(windowsList!)
    }
    
    @objc func menuBarDevHandler(_ sender: NSMenuItem) {
        devList.selectItem(at: sender.tag)
        selectVideoDev(devList!)
    }
    
    private func setup(list: NSPopUpButton) {
        liveWindow = liveWindow ?? LiveWindow()
        let title = list.selectedItem?.title
        liveContentIndicator.stringValue = (title == "-- None --") ? "Nothing" : (title ?? "")
    }
    
    private func setupPresenterTimer() {
        presenterTimer.onTick = {[weak self] timeString in DispatchQueue.main.async {
            self?.timerText.stringValue = timeString
            self?.menuBarShortcuts.updateMenuBarTimer(with: timeString)
            }
        }
    }
    
    private func startOrStopPresenterTimer() {
        if !isTimerRunning {
            isTimerRunning = true
            timerButtonLabel.stringValue = "Pause Timer"
            let systemFont = NSFont.systemFont(ofSize: 20.0, weight: .heavy)
            timerText.font = systemFont
            presenterTimer.startTimer()
        } else {
            isTimerRunning = false
            timerButtonLabel.stringValue = "Resume Timer"
            let systemFont = NSFont.systemFont(ofSize: 20.0, weight: .light)
            timerText.font = systemFont
            presenterTimer.pauseTimer()
        }
    }
    
    private func refreshMenuBarItems() {
        updateSubMenuItems(menu: menuBarShortcuts.windowSubMenu, from: windowsList, action: #selector(menuBarWindowsHandler(_:)))
        updateSubMenuItems(menu: menuBarShortcuts.deviceSubMenu, from: devList, action: #selector(menuBarDevHandler(_:)))
        refreshMenuBarScreens(menu: menuBarShortcuts.screenSubMenu)
    }
    
    private func refreshMenuBarScreens(menu: NSMenu) {
        refreshScreens(menu)
    }
    
    private func refreshScreens(_ menu: NSMenu) {
        menu.removeAllItems()
        let screens = NSScreen.screens
        
        for (index, screen) in screens.enumerated() {
            let screenName = screenSwitcher.getScreenNameOrResolution(screen: screen)
            let screenMenuItem = NSMenuItem(title: screenName, action: #selector(switchLiveWindowScreen(_:)), keyEquivalent: "")
            screenMenuItem.tag = index
            screenMenuItem.target = self
            menu.addItem(screenMenuItem)
        }
    }
    
    private func updateSubMenuItems(menu: NSMenu, from popup: NSPopUpButton, action: Selector) {
        menu.removeAllItems()
        for item in popup.itemArray {
            let newItem = NSMenuItem(title: item.title, action: action, keyEquivalent: "")
            newItem.target = self
            newItem.tag = popup.index(of: item)
            menu.addItem(newItem)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        /// NOTE: comment out the following if-statement when building on Xcode 10, or it won't build.
//        if #available(macOS 10.15, *) {
//            CGRequestScreenCaptureAccess()
//        }
        
        AppDelegate.sharedPlaceholder = self
        if let menu = menuBarShortcuts.menuBarItem.menu {
            menu.delegate = self
        }
        windowsList.addItem(withTitle: "-- None --")
        devList.addItem(withTitle: "-- None --")
        windows.setup(popup: windowsList)
        videoDevs.setup(popup: devList)
        setupPresenterTimer()
        refreshMenuBarItems()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let toggleItem = menuBarShortcuts.toggleMenuItem {
            if isTimerRunning {
                toggleItem.title = "Pause Timer"
            } else {
                if presenterTimer.totalSeconds > 0 {
                    toggleItem.title = "Resume Timer"
                } else {
                    toggleItem.title = "Start Timer"
                }
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {}
    
}
