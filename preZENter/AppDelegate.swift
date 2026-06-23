import Cocoa
import CoreAudio
import CoreGraphics

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var liveContentIndicator: NSTextField!
    @IBOutlet weak var timerText: NSTextField!
    @IBOutlet weak var contentChooser: NSTabView!
    
    private enum ContentSource: Equatable {
        case window(Int), screen(Int), video(Int)
        
        var dataIndex: Int {
            switch self { case .window(let index), .screen(let index), .video(let index): return index }
        }
        
        var title: String {
            switch self {
            case .window: return "window"
            case .screen: return "screen"
            case .video: return "video"
            }
        }
    }
    
    // MARK: - Select indices
    
    private var selectedSource: ContentSource? = nil
    
    private var selectedWindowIndex: Int? {
        get { if case .window(let index) = selectedSource { return index } else { return nil } }
        set { selectedSource = newValue.map { .window($0) } }
    }
    
    private var selectedScreenIndex: Int? {
        get { if case .screen(let index) = selectedSource { return index } else { return nil } }
        set { selectedSource = newValue.map { .screen($0) } }
    }
    
    private var selectedVideoIndex: Int? {
        get { if case .video(let index) = selectedSource { return index } else { return nil } }
        set { selectedSource = newValue.map { .video($0) } }
    }
    
    // MARK: - Data model
    // Index - 0: "--None--"; index 1+: actual content; ...Items[i]: index "i+1"
    private var windowItems: [(title: String, windowID: CGWindowID)] = []
    private var screenItems: [(title: String, displayID: CGDirectDisplayID)] = []
    private var videoItems: [String] = []
    
    // MARK: - Components
    private var liveWindow: LiveWindow?
    private var videoDevs = VideoCaptureDevs()
    private var windows = Windows()
    private var screens = Screens()
    private var menuBarShortcuts = MenuBarShortcuts()
    private var isTimerRunning = false
    
    private let presenterTimer = PresenterTimer()
    private let switchers = Switchers()
    
    // MARK: - Grid views
    private var windowGridView: ContentGridView?
    private var screenGridView: ContentGridView?
    private var videoGridView: ContentGridView?
    
    // MARK: - XIB action connections
    
    @IBAction func getLatestRelease(_ sender: AnyObject) {
        NSWorkspace.shared.open(URL(string: "https://github.com/homeofhx/preZENter/releases/latest")!)
    }
    
    @IBAction func refreshContents(_ sender: Any) {
        windowItems = windows.getVisibleWindows()
        videoItems = videoDevs.getDeviceNames()
        screenItems = screens.getAllScreens()
        refreshMenuBarItems()
        refreshAllGrids()
    }
    
    @IBAction func presenterTimerButtonPressed(_ sender: Any) {
        startOrStopPresenterTimer()
    }
    
    @IBAction func showScreenList(_ sender: NSButton) {
        let menu = NSMenu(title: "Select a Display")
        let data = NSScreen.screens.enumerated().map { (switchers.getDisplayInfo(screen: $0.element), $0.offset) }
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
    
    @IBAction func stopPresenting(_ sender: Any) {
        let wasPresenting = selectedSource != nil
        deselectAllContent()
        setupLiveWindow(selectedTitle: nil)
        
        guard wasPresenting, let lw = liveWindow else {
            liveWindow?.showIdleScreen()
            return
        }
        
        lw.performTransition {
            self.stopAllSessions()
            lw.showIdleScreen()
        }
    }
    
    // MARK: - Select input source
    
    private func selectSource(_ source: ContentSource?) {
        let title: String?
        
        switch source {
        case .window(let i): title = windowItems[safe: i - 1]?.title
        case .screen(let i): title = screenItems[safe: i - 1]?.title
        case .video(let i): title = videoItems[safe: i - 1]
        case .none: title = nil
        }
        
        setupLiveWindow(selectedTitle: title)
        
        liveWindow?.performTransition {
            self.stopAllSessions()
            
            guard let source = source else {
                self.liveWindow?.showIdleScreen()
                return
            }
            
            switch source {
            case .window(let i):
                guard let id = self.windowItems[safe: i - 1]?.windowID else { self.handleSourceLost(); return }
                self.liveWindow?.hideIdleScreen()
                self.windows.selectWindow(id: id, liveWindow: self.liveWindow!)
            case .screen(let i):
                guard let displayID = self.screenItems[safe: i - 1]?.displayID else { self.handleSourceLost(); return }
                self.liveWindow?.hideIdleScreen()
                self.screens.selectScreen(displayID: displayID, liveWindow: self.liveWindow!)
            case .video(let i):
                guard self.videoItems[safe: i - 1] != nil else { self.handleSourceLost(); return }
                self.liveWindow?.hideIdleScreen()
                self.videoDevs.selectVideoDev(at: i - 1, liveWindow: self.liveWindow!)
            }
        }
    }
    
    private func stopAllSessions() {
        guard let lw = liveWindow else { return }
        windows.stopWindowSession(liveWindow: lw)
        screens.stopScreenSession(liveWindow: lw)
        videoDevs.stopVideoDevSession(liveWindow: lw)
    }
    
    private func deselectAllContent() {
        windowGridView?.deselectAll()
        screenGridView?.deselectAll()
        videoGridView?.deselectAll()
        selectedSource = nil
    }
    
    // MARK: - Menu Bar Shortcuts handlers
    
    @objc func menuBarPresenterTimerHandler() {
        startOrStopPresenterTimer()
    }
    
    @objc func menuBarWindowHandler(_ sender: NSMenuItem) {
        let source: ContentSource? = sender.tag > 0 ? .window(sender.tag) : nil
        selectedSource = source
        syncAllGridsToSelection()
        selectSource(source)
    }
    
    @objc func menuBarDevHandler(_ sender: NSMenuItem) {
        let source: ContentSource? = sender.tag > 0 ? .video(sender.tag) : nil
        selectedSource = source
        syncAllGridsToSelection()
        selectSource(source)
    }
    
    @objc func menuBarScreenHandler(_ sender: NSMenuItem) {
        let source: ContentSource? = sender.tag > 0 ? .screen(sender.tag) : nil
        selectedSource = source
        syncAllGridsToSelection()
        selectSource(source)
    }
    
    @objc func menuBarScreenSwitcherHandler(_ sender: NSMenuItem) {
        if liveWindow == nil { liveWindow = LiveWindow() }
        if let win = liveWindow?.window { switchers.moveLiveWindowToSelectedDisplay(window: win, to: sender.tag) }
    }
    
    @objc func menuBarAudioOutputDeviceHandler(_ sender: NSMenuItem) {
        switchers.setAudioOutputDevice(to: AudioDeviceID(sender.tag))
    }
    
    @objc func menuBarStopPresentingHandler() {
        stopPresenting(self)
    }
    
    // MARK: - Setup
    
    private func setupLiveWindow(selectedTitle: String?) {
        liveWindow = liveWindow ?? LiveWindow()
        let title = selectedTitle ?? ""
        liveContentIndicator.stringValue = title.isEmpty ? "Nothing" : title
        menuBarShortcuts.updatePresentingIndicator(with: title)
    }
    
    private func setupPresenterTimer() {
        presenterTimer.onTick = { [weak self] timeString in
            DispatchQueue.main.async {
                self?.timerText.stringValue = timeString
                self?.menuBarShortcuts.updateMenuBarTimer(with: timeString)
            }
        }
    }
    
    private func setupSourceLostHandlers() {
        let handler: () -> Void = { [weak self] in self?.handleSourceLost() }
        windows.onWindowLost = handler
        screens.onSourceLost = handler
        videoDevs.onVideoDevLost = handler
    }
    
    private func handleSourceLost() {
        guard liveWindow != nil else { return }
        deselectAllContent()
        setupLiveWindow(selectedTitle: nil)
        liveWindow?.performTransition {
            self.stopAllSessions()
            self.liveWindow?.showIdleScreen()
        }
    }
    
    private func startOrStopPresenterTimer() {
        isTimerRunning.toggle()
        timerText.font = .systemFont(ofSize: 20.0, weight: isTimerRunning ? .heavy : .light)
        isTimerRunning ? presenterTimer.startTimer() : presenterTimer.pauseTimer()
    }
    
    // MARK: - Menu Bar Shortcuts items
    
    private func refreshMenuBarItems() {
        // Tag 0 = Stop presenting; tag N = item at data-array index N-1.
        let windowData = windowItems.enumerated().map { ($0.element.title, $0.offset + 1) }
        updateSubMenuItems(menuBarShortcuts.windowSubMenu, from: windowData, action: #selector(menuBarWindowHandler))
        
        let videoData = videoItems.enumerated().map { ($0.element, $0.offset + 1) }
        updateSubMenuItems(menuBarShortcuts.deviceSubMenu, from: videoData, action: #selector(menuBarDevHandler))
        
        let screenData = screenItems.enumerated().map { ($0.element.title, $0.offset + 1) }
        updateSubMenuItems(menuBarShortcuts.screenSubMenu, from: screenData, action: #selector(menuBarScreenHandler))
        
        let displayData = NSScreen.screens.enumerated().map { (switchers.getDisplayInfo(screen: $0.element), $0.offset) }
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
    
    // MARK: - Content Chooser grids
    
    private func dataIndexToGridIndex(_ dataIndex: Int?) -> Int? {
        guard let i = dataIndex, i > 0 else { return nil }
        return i - 1
    }
    
    private func setupContentGrids() {
        guard let tabView = contentChooser else { return }
        
        for tabItem in tabView.tabViewItems {
            guard let contentView = tabItem.view else { continue }
            
            let scrollView = NSScrollView(frame: contentView.bounds)
            scrollView.autoresizingMask = [.width, .height]
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            
            let gridView = ContentGridView(frame: NSRect(origin: .zero, size: contentView.bounds.size))
            scrollView.documentView = gridView
            contentView.addSubview(scrollView)
            
            switch tabItem.label {
            case "App Window": windowGridView = gridView
            case "Screen": screenGridView = gridView
            case "Video Device": videoGridView  = gridView
            default: break
            }
        }
    }
    
    private func refreshAllGrids() {
        refreshWindowGrid()
        refreshScreenGrid()
        refreshVideoDevGrid()
    }
    
    private func refreshGrid(_ grid: ContentGridView,
                             selectedIndex: Int?,
                             fetchItems: @escaping () -> [(name: String, thumbnail: NSImage?)],
                             onSelect: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            let items = fetchItems()
            DispatchQueue.main.async {
                grid.populateGridItems(items: items, selectedIndex: selectedIndex, onSelect: onSelect)
            }
        }
    }
    
    private func refreshWindowGrid() {
        guard let grid = windowGridView else { return }
        refreshGrid(grid,
                    selectedIndex: dataIndexToGridIndex(selectedWindowIndex),
                    fetchItems: { [weak self] in
            guard let self = self else { return [] }
            return self.windowItems.map { window in
                let thumb = CGWindowListCreateImage(.null,
                                                    .optionIncludingWindow,
                                                    window.windowID,
                                                    [.bestResolution, .boundsIgnoreFraming])
                    .map { NSImage(cgImage: $0, size: .zero) }
                return (window.title, thumb)
            }
        }, onSelect: { [weak self] gridIndex in
            guard let self = self else { return }
            let source = ContentSource.window(gridIndex + 1)
            self.selectedSource = source
            self.screenGridView?.deselectAll()
            self.videoGridView?.deselectAll()
            self.selectSource(source)
        })
    }
    
    private func refreshScreenGrid() {
        guard let grid = screenGridView else { return }
        refreshGrid(grid,
                    selectedIndex: dataIndexToGridIndex(selectedScreenIndex),
                    fetchItems: { [weak self] in
            guard let self = self else { return [] }
            return self.screenItems.map { screen in
                let thumb = CGDisplayCreateImage(screen.displayID).map { NSImage(cgImage: $0, size: .zero) }
                return (screen.title, thumb)
            }
        }, onSelect: { [weak self] gridIndex in
            guard let self = self else { return }
            let source = ContentSource.screen(gridIndex + 1)
            self.selectedSource = source
            self.windowGridView?.deselectAll()
            self.videoGridView?.deselectAll()
            self.selectSource(source)
        })
    }
    
    private func refreshVideoDevGrid() {
        guard let grid = videoGridView else { return }
        let items = videoItems.map {
            name -> (name: String, thumbnail: NSImage?) in
            (name, ContentSourceCardView.videoDevThumbnail(size: NSSize(width: 160, height: 90)))}
        
        grid.populateGridItems(items: items,
                               selectedIndex: dataIndexToGridIndex(selectedVideoIndex)) { [weak self] gridIndex in
            guard let self = self else { return }
            let source = ContentSource.video(gridIndex + 1)
            self.selectedSource = source
            self.windowGridView?.deselectAll()
            self.screenGridView?.deselectAll()
            self.selectSource(source)
        }
    }
    
    private func syncAllGridsToSelection() {
        windowGridView?.deselectAll()
        screenGridView?.deselectAll()
        videoGridView?.deselectAll()
        
        guard
            let source = selectedSource,
            let gridIdx = dataIndexToGridIndex(source.dataIndex) else { return }
        
        switch source {
        case .window: windowGridView?.selectContentCard(at: gridIdx)
        case .screen: screenGridView?.selectContentCard(at: gridIdx)
        case .video: videoGridView?.selectContentCard(at: gridIdx)
        }
    }
    
    // MARK: - AppKit lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let menu = menuBarShortcuts.menuBarItem.menu { menu.delegate = self }
        windowItems = windows.getVisibleWindows()
        videoItems = videoDevs.getDeviceNames()
        screenItems = screens.getAllScreens()
        setupPresenterTimer()
        setupSourceLostHandlers()
        refreshMenuBarItems()
        setupContentGrids()
        refreshAllGrids()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuBarItems()
        menuBarShortcuts.toggleMenuItem?.title = isTimerRunning ? "Pause Timer" :
        (presenterTimer.totalSeconds > 0 ? "Resume Timer" : "Start Timer")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {}
    
}
