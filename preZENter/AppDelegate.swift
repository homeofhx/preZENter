import Cocoa
import CoreAudio

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
    private let switchers = Switchers()
    
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
        windows.refreshWindows(popup: windowsList)
        videoDevs.refreshDevs(popup: devList)
        refreshMenuBarItems()
    }
    
    @IBAction func presenterTimerButtonPressed(_ sender: Any) {
        startOrStopPresenterTimer()
    }
    
    @IBAction func showScreenList(_ sender: NSButton) {
        let screenList = NSMenu(title: "Select a Screen")
        let screenData = NSScreen.screens.enumerated().map {
            (switchers.getScreenNameOrResolution(screen: $0.element), $0.offset)
        }
        updateSubMenuItems(screenList, from: screenData, action: #selector(switchLiveWindowScreen(_:)))
        let point = NSPoint(x: 0, y: sender.frame.height)
        screenList.popUp(positioning: nil, at: point, in: sender)
    }
    
    @IBAction func showAudioOutputDeviceList(_ sender: NSButton) {
        let audioOutputList = NSMenu(title: "Select an Audio Output Device")
        let deviceIDs = switchers.getAudioOutputDeviceIDs()
        
        if deviceIDs.isEmpty {
            audioOutputList.addItem(withTitle: "No Output Devices Found", action: nil, keyEquivalent: "")
        } else {
            let audioData = deviceIDs.map { (switchers.getAudioOutputDeviceName(deviceID: $0), Int($0)) }
            updateSubMenuItems(audioOutputList, from: audioData, action: #selector(menuBarAudioOutputDeviceHandler(_:)))
        }
        
        let point = NSPoint(x: 0, y: sender.frame.height)
        audioOutputList.popUp(positioning: nil, at: point, in: sender)
    }
    
    @objc func switchLiveWindowScreen(_ sender: NSMenuItem) {
        if liveWindow == nil {
            setup(list: windowsList)
        }
        
        if let liveWinInstance = liveWindow?.window {
            switchers.moveLiveWindowToSelectedScreen(window: liveWinInstance, to: sender.tag)
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
    
    @objc func menuBarAudioOutputDeviceHandler(_ sender: NSMenuItem) {
        switchers.setAudioOutputDevice(to: AudioDeviceID(sender.tag))
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
        isTimerRunning.toggle()
        timerButtonLabel.stringValue = isTimerRunning ? "Pause Timer" : "Resume Timer"
        timerText.font = .systemFont(ofSize: 20.0, weight: isTimerRunning ? .heavy : .light)
        isTimerRunning ? presenterTimer.startTimer() : presenterTimer.pauseTimer()
    }
    
    private func refreshMenuBarItems() {
        let windowData = windowsList.itemArray.enumerated().map { ($0.element.title, $0.offset) }
        updateSubMenuItems(menuBarShortcuts.windowSubMenu, from: windowData, action: #selector(menuBarWindowsHandler))
        
        let videoDevData = devList.itemArray.enumerated().map { ($0.element.title, $0.offset) }
        updateSubMenuItems(menuBarShortcuts.deviceSubMenu, from: videoDevData, action: #selector(menuBarDevHandler))
        
        let screenData = NSScreen.screens.enumerated().map {
            (switchers.getScreenNameOrResolution(screen: $0.element), $0.offset)
        }
        updateSubMenuItems(menuBarShortcuts.screenSubMenu, from: screenData, action: #selector(switchLiveWindowScreen))
        
        let audioOutputDevData = switchers.getAudioOutputDeviceIDs().map {
            (switchers.getAudioOutputDeviceName(deviceID: $0), Int($0))
        }
        updateSubMenuItems(menuBarShortcuts.audioOutputSubMenu, from: audioOutputDevData, action: #selector(menuBarAudioOutputDeviceHandler))
    }
    
    private func updateSubMenuItems(_ menu: NSMenu, from items: [(title: String, tag: Int)], action: Selector) {
        menu.removeAllItems()
        for item in items {
            let menuItem = NSMenuItem(title: item.title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = item.tag
            menu.addItem(menuItem)
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
        refreshMenuBarItems()
        menuBarShortcuts.toggleMenuItem?.title = isTimerRunning ? "Pause Timer" : (presenterTimer.totalSeconds > 0 ? "Resume Timer" : "Start Timer")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {}
    
}
