import Cocoa
import CoreAudio
import CoreGraphics

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var liveContentIndicator: NSTextField!
    @IBOutlet weak var timerText: NSTextField!
    @IBOutlet weak var contentPicker: NSTabView!
    
    public static var sharedPlaceholder: AppDelegate!

    // Data model for contents
    // Index 0: "--None--"; index 1+: actual content; ...Items[i]: index i+1
    private var windowItems: [(title: String, windowID: CGWindowID)] = []
    private var screenItems: [(title: String, displayID: CGDirectDisplayID)] = []
    private var videoItems: [String] = []
    
    // Components
    private var liveWindow: LiveWindow?
    private var videoDevs = VideoCaptureDevs()
    private var windows = Windows()
    private var screens = Screens()
    private let presenterTimer = PresenterTimer()
    private var isTimerRunning = false
    private var menuBarShortcuts = MenuBarShortcuts()
    private let switchers = Switchers()
    
    // Grid views
    private var windowGridView: ContentGridView?
    private var screenGridView: ContentGridView?
    private var videoGridView: ContentGridView?
    
    // Selected content's index (0 = None; 1+ = content)
    private var selectedWindowIndex: Int? = nil
    private var selectedScreenIndex: Int? = nil
    private var selectedVideoIndex: Int? = nil
    
    @IBAction func getLatestRelease(_ sender: AnyObject) {
        NSWorkspace.shared.open(URL(string: "https://github.com/homeofhx/preZENter/releases/latest")!)
    }
    
    @IBAction func refreshContents(_ sender: Any) {
        windowItems = windows.getItems()
        videoItems = videoDevs.getDeviceNames()
        screenItems = screens.getItems()
        refreshMenuBarItems()
        refreshAllGrids()
    }
    
    @IBAction func presenterTimerButtonPressed(_ sender: Any) {
        startOrStopPresenterTimer()
    }
    
    @IBAction func showScreenList(_ sender: NSButton) {
        let menu = NSMenu(title: "Select a Screen")
        let data = NSScreen.screens.enumerated().map { (switchers.getScreenNameOrResolution(screen: $0.element), $0.offset) }
        updateSubMenuItems(menu, from: data, action: #selector(menuBarScreenSwitcherHandler(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }
    
    @IBAction func showAudioOutputDeviceList(_ sender: NSButton) {
        let menu = NSMenu(title: "Select an Audio Output Device")
        let deviceIDs = switchers.getAudioOutputDeviceIDs()
        if deviceIDs.isEmpty {
            menu.addItem(withTitle: "No Output Devices Found", action: nil, keyEquivalent: "")
        } else {
            let data = deviceIDs.map { (switchers.getAudioOutputDeviceName(deviceID: $0), Int($0)) }
            updateSubMenuItems(menu, from: data, action: #selector(menuBarAudioOutputDeviceHandler(_:)))
        }
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }
    
    @IBAction func showIdleScreenSettings(_ sender: Any) {
        IdleScreenSettings.shared.showIdleScreenSettings()
    }
    
    // Select input source
    
    private func selectWindowItem(at index: Int) {
        let title = index == 0 ? nil : windowItems[safe: index - 1]?.title
        setupLiveWindow(selectedTitle: title)
        liveWindow!.performTransition {
            if index == 0 {
                self.windows.stopWindowSession(liveWindow: self.liveWindow!)
                self.videoDevs.stopVideoDevSession(liveWindow: self.liveWindow!)
                self.screens.stopScreenSession(liveWindow: self.liveWindow!)
                self.liveWindow?.showIdleScreen()
            } else if let id = self.windowItems[safe: index - 1]?.windowID {
                self.liveWindow?.hideIdleScreen()
                self.videoDevs.stopVideoDevSession(liveWindow: self.liveWindow!)
                self.screens.stopScreenSession(liveWindow: self.liveWindow!)
                self.windows.selectWindow(id: id, liveWindow: self.liveWindow!)
            }
        }
    }
    
    private func selectScreenItem(at index: Int) {
        let title = index == 0 ? nil : screenItems[safe: index - 1]?.title
        setupLiveWindow(selectedTitle: title)
        liveWindow!.performTransition {
            if index == 0 {
                self.screens.stopScreenSession(liveWindow: self.liveWindow!)
                self.windows.stopWindowSession(liveWindow: self.liveWindow!)
                self.videoDevs.stopVideoDevSession(liveWindow: self.liveWindow!)
                self.liveWindow?.showIdleScreen()
            } else if let displayID = self.screenItems[safe: index - 1]?.displayID {
                self.liveWindow?.hideIdleScreen()
                self.windows.stopWindowSession(liveWindow: self.liveWindow!)
                self.videoDevs.stopVideoDevSession(liveWindow: self.liveWindow!)
                self.screens.selectScreen(displayID: displayID, liveWindow: self.liveWindow!)
            }
        }
    }
    
    private func selectVideoItem(at index: Int) {
        let title = index == 0 ? nil : videoItems[safe: index - 1]
        setupLiveWindow(selectedTitle: title)
        liveWindow!.performTransition {
            if index == 0 {
                self.videoDevs.stopVideoDevSession(liveWindow: self.liveWindow!)
                self.windows.stopWindowSession(liveWindow: self.liveWindow!)
                self.screens.stopScreenSession(liveWindow: self.liveWindow!)
                self.liveWindow?.showIdleScreen()
            } else {
                self.liveWindow?.hideIdleScreen()
                self.windows.stopWindowSession(liveWindow: self.liveWindow!)
                self.screens.stopScreenSession(liveWindow: self.liveWindow!)
                self.videoDevs.selectDev(at: index - 1, liveWindow: self.liveWindow!)
            }
        }
    }
    
    // Menu Bar Shortcut handlers
    
    @objc func menuBarPresenterTimerHandler() {
        startOrStopPresenterTimer()
    }
    
    @objc func menuBarWindowHandler(_ sender: NSMenuItem) {
        selectWindowItem(at: sender.tag)
        syncGridSelection(windowGrid: sender.tag)
    }
    
    @objc func menuBarDevHandler(_ sender: NSMenuItem) {
        selectVideoItem(at: sender.tag)
        syncGridSelection(videoGrid: sender.tag)
    }
    
    @objc func menuBarScreenHandler(_ sender: NSMenuItem) {
        selectScreenItem(at: sender.tag)
        syncGridSelection(screenGrid: sender.tag)
    }
    
    @objc func menuBarScreenSwitcherHandler(_ sender: NSMenuItem) {
        if liveWindow == nil { liveWindow = LiveWindow() }
        if let win = liveWindow?.window {
            switchers.moveLiveWindowToSelectedScreen(window: win, to: sender.tag)
        }
    }
    
    @objc func menuBarAudioOutputDeviceHandler(_ sender: NSMenuItem) {
        switchers.setAudioOutputDevice(to: AudioDeviceID(sender.tag))
    }
    
    private func setupLiveWindow(selectedTitle: String?) {
        liveWindow = liveWindow ?? LiveWindow()
        let title = selectedTitle ?? ""
        liveContentIndicator.stringValue = title.isEmpty ? "Nothing" : title
    }
    
    private func setupPresenterTimer() {
        presenterTimer.onTick = { [weak self] timeString in
            DispatchQueue.main.async {
                self?.timerText.stringValue = timeString
                self?.menuBarShortcuts.updateMenuBarTimer(with: timeString)
            }
        }
    }
    
    private func startOrStopPresenterTimer() {
        isTimerRunning.toggle()
        timerText.font = .systemFont(ofSize: 20.0, weight: isTimerRunning ? .heavy : .light)
        isTimerRunning ? presenterTimer.startTimer() : presenterTimer.pauseTimer()
    }
    
    private func refreshMenuBarItems() {
        // Tag 0 = "None", tag N = real item at data-array index N-1.
        let windowData: [(String, Int)] = [("-- None --", 0)] + windowItems.enumerated().map { ($0.element.title, $0.offset + 1) }
        updateSubMenuItems(menuBarShortcuts.windowSubMenu, from: windowData, action: #selector(menuBarWindowHandler))
        
        let videoData: [(String, Int)] = [("-- None --", 0)] + videoItems.enumerated().map { ($0.element, $0.offset + 1) }
        updateSubMenuItems(menuBarShortcuts.deviceSubMenu, from: videoData, action: #selector(menuBarDevHandler))

        let screenData: [(String, Int)] = [("-- None --", 0)] + screenItems.enumerated().map { ($0.element.title, $0.offset + 1) }
        updateSubMenuItems(menuBarShortcuts.screenSubMenu, from: screenData, action: #selector(menuBarScreenHandler))
        
        let displayData = NSScreen.screens.enumerated().map { (switchers.getScreenNameOrResolution(screen: $0.element), $0.offset) }
        updateSubMenuItems(menuBarShortcuts.displaySubMenu, from: displayData, action: #selector(menuBarScreenSwitcherHandler))
        
        let audioData = switchers.getAudioOutputDeviceIDs().map { (switchers.getAudioOutputDeviceName(deviceID: $0), Int($0)) }
        updateSubMenuItems(menuBarShortcuts.audioOutputSubMenu, from: audioData, action: #selector(menuBarAudioOutputDeviceHandler))
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
    
    private func setupContentGrids() {
        guard let tabView = contentPicker else { return }
        
        for tabItem in tabView.tabViewItems {
            guard let contentView = tabItem.view else { continue }
            
            let scrollView = NSScrollView(frame: contentView.bounds)
            scrollView.autoresizingMask = [.width, .height]
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            
            let gridView = ContentGridView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height))
            scrollView.documentView = gridView
            contentView.addSubview(scrollView)
            
            switch tabItem.label {
                case "App Window": windowGridView = gridView
                case "Screen": screenGridView = gridView
                case "Video Device": videoGridView = gridView
                default: break
            }
        }
    }
    
    private func refreshAllGrids() {
        refreshWindowGrid()
        refreshScreenGrid()
        refreshVideoGrid()
    }
    
    private func refreshWindowGrid() {
        guard let grid = windowGridView else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var items: [(name: String, thumbnail: NSImage?)] = [("Stop Presenting", ContentSourceCardView.noSourceThumbnail(size: NSSize(width: 160, height: 90)))]
            
            for window in self.windowItems {
                let thumb: NSImage? = {
                    guard let ref = CGWindowListCreateImage(.null, .optionIncludingWindow, window.windowID, [.bestResolution, .boundsIgnoreFraming]) else { return nil }
                    return NSImage(cgImage: ref, size: .zero)
                }()
                items.append((window.title, thumb))
            }
            
            DispatchQueue.main.async {
                grid.populateGridItems(items: items, selectedIndex: self.selectedWindowIndex) { [weak self] index in
                    guard let self = self else { return }
                    self.selectedWindowIndex = index
                    self.selectedScreenIndex = nil
                    self.selectedVideoIndex = nil
                    self.screenGridView?.deselectAll()
                    self.videoGridView?.deselectAll()
                    self.selectWindowItem(at: index)
                }
            }
        }
    }
    
    private func refreshScreenGrid() {
        guard let grid = screenGridView else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var items: [(name: String, thumbnail: NSImage?)] = [("Stop Presenting", ContentSourceCardView.noSourceThumbnail(size: NSSize(width: 160, height: 90)))]
            
            for screen in self.screenItems {
                let thumb: NSImage? = {
                    guard let ref = CGDisplayCreateImage(screen.displayID) else { return nil }
                    return NSImage(cgImage: ref, size: .zero)
                }()
                items.append((screen.title, thumb))
            }
            
            DispatchQueue.main.async {
                grid.populateGridItems(items: items, selectedIndex: self.selectedScreenIndex) { [weak self] index in
                    guard let self = self else { return }
                    self.selectedScreenIndex = index
                    self.selectedWindowIndex = nil
                    self.selectedVideoIndex = nil
                    self.windowGridView?.deselectAll()
                    self.videoGridView?.deselectAll()
                    self.selectScreenItem(at: index)
                }
            }
        }
    }
    
    private func refreshVideoGrid() {
        guard let grid = videoGridView else { return }
        var items: [(name: String, thumbnail: NSImage?)] = [("Stop Presenting", ContentSourceCardView.noSourceThumbnail(size: NSSize(width: 160, height: 90)))]
        
        for name in videoItems {
            let thumb = ContentSourceCardView.videoDevThumbnail(size: NSSize(width: 160, height: 90))
            items.append((name, thumb))
        }
        
        grid.populateGridItems(items: items, selectedIndex: selectedVideoIndex) { [weak self] index in
            guard let self = self else { return }
            self.selectedVideoIndex  = index
            self.selectedWindowIndex = nil
            self.selectedScreenIndex = nil
            self.windowGridView?.deselectAll()
            self.screenGridView?.deselectAll()
            self.selectVideoItem(at: index)
        }
    }
    
    // Content selection sync
    private func syncGridSelection(windowGrid win: Int? = nil, screenGrid scr: Int? = nil, videoGrid vid: Int? = nil) {
        if let index = win {
            selectedWindowIndex = index
            selectedScreenIndex = nil
            selectedVideoIndex = nil
            windowGridView?.selectCard(at: index)
            screenGridView?.deselectAll()
            videoGridView?.deselectAll()
        } else if let index = scr {
            selectedScreenIndex = index
            selectedWindowIndex = nil
            selectedVideoIndex = nil
            screenGridView?.selectCard(at: index)
            windowGridView?.deselectAll()
            videoGridView?.deselectAll()
        } else if let index = vid {
            selectedVideoIndex = index
            selectedWindowIndex = nil
            selectedScreenIndex = nil
            videoGridView?.selectCard(at: index)
            windowGridView?.deselectAll()
            screenGridView?.deselectAll()
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppDelegate.sharedPlaceholder = self
        if let menu = menuBarShortcuts.menuBarItem.menu { menu.delegate = self }
        windowItems = windows.getItems()
        videoItems = videoDevs.getDeviceNames()
        screenItems = screens.getItems()
        setupPresenterTimer()
        refreshMenuBarItems()
        setupContentGrids()
        refreshAllGrids()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuBarItems()
        menuBarShortcuts.toggleMenuItem?.title = isTimerRunning ? "Pause Timer" : (presenterTimer.totalSeconds > 0 ? "Resume Timer" : "Start Timer")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {}
}

// Safe array subscript helper
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
