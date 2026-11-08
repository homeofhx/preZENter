import Cocoa
import CoreAudio
import CoreGraphics

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    @IBOutlet private weak var window: NSWindow!
    @IBOutlet private weak var liveContentIndicator: NSTextField!
    @IBOutlet private weak var presentationStatusIndicator: NSButton!
    @IBOutlet private weak var timerText: NSTextField!
    @IBOutlet private weak var contentChooser: NSTabView!

    private var catalog = ContentSourceCatalog()
    private var selectedSource: ContentSource?
    private let sourceDiscovery = ContentSourceDiscovery()

    private var liveWindow: LiveWindow? {
        didSet {
            liveWindow?.onPresentationStatusChanged = { [weak self] isPresenting in
                self?.updatePresentationStatus(isPresenting: isPresenting)
            }
            updatePresentationStatus(isPresenting: liveWindow?.isPresenting ?? false)
        }
    }
    private var presentationCoordinator: PresentationCoordinator?
    private let systemSwitcher = SystemSwitcher()
    private let presenterTimer = PresenterTimer()
    private let menuBarShortcuts = MenuBarShortcuts()
    private var isTimerRunning = false

    private var contentAutoRefreshTimer: Timer?
    private static let autoRefreshInterval: TimeInterval = 2.0
    private var gridRefreshID: UInt64 = 0

    private var windowGridView: ContentGridView?
    private var screenGridView: ContentGridView?
    private var videoGridView: ContentGridView?
    private var iOSDeviceGridView: ContentGridView?

    // MARK: - Control Panel actions

    @IBAction private func getLatestRelease(_ sender: AnyObject) {
        guard let url = URL(string: "https://github.com/homeofhx/preZENter/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }

    @IBAction func refreshContents(_ sender: Any) {
        refreshContentCatalog(forceUIRefresh: true)
    }

    private func refreshContentCatalog(forceUIRefresh: Bool) {
        let sourceBeforeRefresh = selectedSource
        let catalogChanged = catalog.merge(sourceDiscovery.discover())
        if forceUIRefresh || catalogChanged {
            refreshMenuBarItems()
            refreshAllGrids()
        }

        if let source = sourceBeforeRefresh, !catalog.contains(source) { handleSourceLost(source) }
    }

    @IBAction private func presenterTimerButtonPressed(_ sender: Any) {
        startOrStopPresenterTimer()
    }

    @IBAction private func showScreenList(_ sender: NSButton) {
        let menu = NSMenu(title: "Select a Display")
        let items = NSScreen.screens.enumerated().map { (systemSwitcher.displayName(for: $0.element), $0.offset) }
        updateSubMenuItems(menu, from: items, action: #selector(menuBarScreenSwitcherHandler(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }

    @IBAction private func showAudioOutputDeviceList(_ sender: NSButton) {
        let menu = NSMenu(title: "Select an Audio Output Device")
        let deviceIDs = systemSwitcher.audioOutputDeviceIDs()
        if deviceIDs.isEmpty {
            menu.addItem(withTitle: "No Audio Output Devices Found", action: nil, keyEquivalent: "")
        } else {
            let items = deviceIDs.map { (systemSwitcher.audioOutputDeviceName(deviceID: $0), Int($0)) }
            updateSubMenuItems(menu, from: items, action: #selector(menuBarAudioOutputDeviceHandler(_:)))
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender)
    }

    @IBAction private func showIdleScreenSettings(_ sender: Any) {
        IdleScreenSettings.shared.showIdleScreenSettings()
    }

    @IBAction func stopPresenting(_ sender: Any) {
        selectedSource = nil
        syncAllGridsToSelection()
        setupLiveWindow(selectedTitle: nil)

        liveWindow?.performTransition { [weak self] in
            guard let self = self, self.selectedSource == nil else { return }
            self.presentationCoordinator?.stopAndShowIdle()
        }
    }

    // MARK: - Source selection

    private func selectSource(_ source: ContentSource) {
        guard catalog.contains(source), let title = catalog.title(for: source) else {
            handleSourceLost(source)
            return
        }

        selectedSource = source
        syncAllGridsToSelection()
        setupLiveWindow(selectedTitle: title)
        liveWindow?.performTransition { [weak self] in
            guard let self = self, self.selectedSource == source else { return }
            self.presentationCoordinator?.present(source)
        }
    }

    private func handleSourceLost(_ source: ContentSource) {
        guard selectedSource == source else { return }
        selectedSource = nil
        syncAllGridsToSelection()
        setupLiveWindow(selectedTitle: nil)
        liveWindow?.performTransition { [weak self] in
            guard let self = self, self.selectedSource == nil else { return }
            self.presentationCoordinator?.stopAndShowIdle()
        }
    }

    // MARK: - Menu bar actions

    @objc func menuBarPresenterTimerHandler() {
        startOrStopPresenterTimer()
    }

    @objc func menuBarWindowHandler(_ sender: NSMenuItem) {
        guard let source = sourceFromMenu(sender, kind: .applicationWindow) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            self.selectSource(source)
        }
    }

    @objc func menuBarDevHandler(_ sender: NSMenuItem) {
        if let source = sourceFromMenu(sender, kind: .videoDevice) { selectSource(source) }
    }

    @objc func menuBarIOSDeviceHandler(_ sender: NSMenuItem) {
        if let source = sourceFromMenu(sender, kind: .iOSDevice) { selectSource(source) }
    }

    @objc func menuBarScreenHandler(_ sender: NSMenuItem) {
        if let source = sourceFromMenu(sender, kind: .screen) { selectSource(source) }
    }

    @objc func menuBarScreenSwitcherHandler(_ sender: NSMenuItem) {
        setupLiveWindow(selectedTitle: selectedSource.flatMap { catalog.title(for: $0) })
        if let liveWindow = liveWindow?.window { systemSwitcher.moveLiveWindow(liveWindow, toScreenAt: sender.tag) }
    }

    @objc func menuBarAudioOutputDeviceHandler(_ sender: NSMenuItem) {
        systemSwitcher.setAudioOutputDevice(AudioDeviceID(sender.tag))
    }

    @objc func menuBarStopPresentingHandler() {
        stopPresenting(self)
    }

    private func sourceFromMenu(_ item: NSMenuItem, kind: ContentSourceKind) -> ContentSource? {
        guard item.tag > 0 else { return nil }
        return catalog.source(kind: kind, at: item.tag - 1)
    }

    // MARK: - Presentation UI

    private func setupLiveWindow(selectedTitle: String?) {
        if liveWindow == nil {
            let newLiveWindow = LiveWindow()
            liveWindow = newLiveWindow
            let coordinator = PresentationCoordinator(liveWindow: newLiveWindow)
            coordinator.onSourceLost = { [weak self] source in
                self?.handleSourceLost(source)
            }
            presentationCoordinator = coordinator
        }

        let title = selectedTitle ?? ""
        liveContentIndicator.stringValue = title.isEmpty ? "Nothing" : AppDelegate.truncatedContentName(title)
        menuBarShortcuts.updatePresentingIndicator(with: title)
    }

    private func updatePresentationStatus(isPresenting: Bool) {
        presentationStatusIndicator.image = NSImage(named: isPresenting ? NSImage.statusAvailableName : NSImage.statusUnavailableName)
        presentationStatusIndicator.toolTip = isPresenting ? "Presenting content" : "Not presenting content"
        menuBarShortcuts.updatePresentationStatus(isPresenting: isPresenting)
    }

    private static func truncatedContentName(_ name: String) -> String {
        guard name.count > 42 else { return name }
        return String(name.prefix(42)) + "..."
    }

    // MARK: - Content menus

    private func refreshMenuBarItems() {
        updateSubMenuItems(menuBarShortcuts.windowSubMenu,
                           from: catalog.windows.enumerated().map { ($0.element.title, $0.offset + 1) },
                           action: #selector(menuBarWindowHandler(_:)))
        updateSubMenuItems(menuBarShortcuts.screenSubMenu,
                           from: catalog.screens.enumerated().map { ($0.element.title, $0.offset + 1) },
                           action: #selector(menuBarScreenHandler(_:)))
        updateSubMenuItems(menuBarShortcuts.deviceSubMenu,
                           from: catalog.videoDevices.enumerated().map { ($0.element.name, $0.offset + 1) },
                           action: #selector(menuBarDevHandler(_:)))
        updateSubMenuItems(menuBarShortcuts.iOSDeviceSubMenu,
                           from: catalog.iOSDevices.enumerated().map { ($0.element.name, $0.offset + 1) },
                           action: #selector(menuBarIOSDeviceHandler(_:)))

        let displays = NSScreen.screens.enumerated().map { (systemSwitcher.displayName(for: $0.element), $0.offset) }
        updateSubMenuItems(menuBarShortcuts.displaySubMenu,
                           from: displays,
                           action: #selector(menuBarScreenSwitcherHandler(_:)))

        let audioDevices = systemSwitcher.audioOutputDeviceIDs().map { (systemSwitcher.audioOutputDeviceName(deviceID: $0), Int($0)) }
        updateSubMenuItems(menuBarShortcuts.audioOutputSubMenu,
                           from: audioDevices,
                           action: #selector(menuBarAudioOutputDeviceHandler(_:)))
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

    // MARK: - Content grids

    private func setupContentGrids() {
        for tabItem in contentChooser.tabViewItems {
            guard let contentView = tabItem.view else { continue }
            let scrollView = NSScrollView(frame: contentView.bounds)
            scrollView.autoresizingMask = [.width, .height]
            scrollView.hasVerticalScroller = false
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder

            let gridView = ContentGridView(frame: NSRect(origin: .zero, size: contentView.bounds.size))
            scrollView.documentView = gridView
            contentView.addSubview(scrollView)

            switch tabItem.label {
            case "App Window": windowGridView = gridView
            case "Screen": screenGridView = gridView
            case "Video Device": videoGridView = gridView
            case "iOS Device": iOSDeviceGridView = gridView
            default: break
            }
        }
    }

    private func refreshAllGrids() {
        gridRefreshID &+= 1
        let refreshID = gridRefreshID
        let snapshot = catalog
        refreshWindowGrid(snapshot: snapshot, refreshID: refreshID)
        refreshScreenGrid(snapshot: snapshot, refreshID: refreshID)
        refreshVideoDeviceGrid(snapshot: snapshot)
        refreshIOSDeviceGrid(snapshot: snapshot)
    }

    private func refreshWindowGrid(snapshot: ContentSourceCatalog, refreshID: UInt64) {
        guard let grid = windowGridView else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak grid] in
            let items = snapshot.windows.map { window -> (name: String, thumbnail: NSImage?) in
                let thumbnail = CGWindowListCreateImage(.null,
                                                        .optionIncludingWindow,
                                                        window.windowID,
                                                        [.bestResolution, .boundsIgnoreFraming])
                    .map { NSImage(cgImage: $0, size: .zero) }
                return (window.title, thumbnail)
            }
            DispatchQueue.main.async {
                guard let self = self,
                      let grid = grid,
                      self.gridRefreshID == refreshID else { return }
                grid.populateGridItems(items: items, selectedIndex: self.selectedIndex(in: snapshot,
                                                                                       kind: .applicationWindow)) {
                    [weak self] index in
                    guard let source = snapshot.source(kind: .applicationWindow, at: index) else { return }
                    self?.selectSource(source)
                }
            }
        }
    }

    private func refreshScreenGrid(snapshot: ContentSourceCatalog, refreshID: UInt64) {
        guard let grid = screenGridView else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak grid] in
            let items = snapshot.screens.map { screen -> (name: String, thumbnail: NSImage?) in
                let thumbnail = CGDisplayCreateImage(screen.displayID).map { NSImage(cgImage: $0, size: .zero) }
                return (screen.title, thumbnail)
            }
            DispatchQueue.main.async {
                guard let self = self,
                      let grid = grid,
                      self.gridRefreshID == refreshID else { return }
                grid.populateGridItems(items: items, selectedIndex: self.selectedIndex(in: snapshot, kind: .screen)) {
                    [weak self] index in
                    guard let source = snapshot.source(kind: .screen, at: index) else { return }
                    self?.selectSource(source)
                }
            }
        }
    }

    private func refreshVideoDeviceGrid(snapshot: ContentSourceCatalog) {
        guard let grid = videoGridView else { return }
        let thumbnail = ContentSourceCardView.videoDevThumbnail(size: NSSize(width: 160, height: 90))
        let items = snapshot.videoDevices.map { ($0.name, Optional(thumbnail)) }
        grid.populateGridItems(items: items, selectedIndex: selectedIndex(in: snapshot, kind: .videoDevice)) {
            [weak self] index in
            guard let source = snapshot.source(kind: .videoDevice, at: index) else { return }
            self?.selectSource(source)
        }
    }

    private func refreshIOSDeviceGrid(snapshot: ContentSourceCatalog) {
        guard let grid = iOSDeviceGridView else { return }
        let thumbnail = ContentSourceCardView.iOSDeviceThumbnail(size: NSSize(width: 160, height: 90))
        let items = snapshot.iOSDevices.map { ($0.name, Optional(thumbnail)) }
        grid.populateGridItems(items: items, selectedIndex: selectedIndex(in: snapshot, kind: .iOSDevice)) {
            [weak self] index in
            guard let source = snapshot.source(kind: .iOSDevice, at: index) else { return }
            self?.selectSource(source)
        }
    }

    private func selectedIndex(in snapshot: ContentSourceCatalog, kind: ContentSourceKind) -> Int? {
        guard let selectedSource = selectedSource,
              selectedSource.kind == kind else { return nil }
        return snapshot.index(of: selectedSource)
    }

    private func syncAllGridsToSelection() {
        windowGridView?.deselectAll()
        screenGridView?.deselectAll()
        videoGridView?.deselectAll()
        iOSDeviceGridView?.deselectAll()
        guard let source = selectedSource,
              let index = catalog.index(of: source) else { return }

        switch source.kind {
        case .applicationWindow: windowGridView?.selectContentCard(at: index)
        case .screen: screenGridView?.selectContentCard(at: index)
        case .videoDevice: videoGridView?.selectContentCard(at: index)
        case .iOSDevice: iOSDeviceGridView?.selectContentCard(at: index)
        }
    }

    // MARK: - Timer

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

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.delegate = self
        presentationStatusIndicator.isEnabled = false
        (presentationStatusIndicator.cell as? NSButtonCell)?.imageDimsWhenDisabled = false
        updatePresentationStatus(isPresenting: false)
        menuBarShortcuts.menuBarItem.menu?.delegate = self

        catalog.merge(sourceDiscovery.discover())
        setupPresenterTimer()
        refreshMenuBarItems()
        setupContentGrids()
        refreshAllGrids()
        startContentAutoRefresh()
    }

    private func startContentAutoRefresh() {
        contentAutoRefreshTimer?.invalidate()
        contentAutoRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: AppDelegate.autoRefreshInterval,
            repeats: true) { [weak self] _ in
                self?.refreshContentCatalog(forceUIRefresh: false)
        }
        if let timer = contentAutoRefreshTimer { RunLoop.current.add(timer, forMode: .common) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuBarItems()
        menuBarShortcuts.toggleMenuItem?.title = isTimerRunning ? "Pause Timer" : (presenterTimer.totalSeconds > 0 ? "Resume Timer" : "Start Timer")
    }

    func applicationWillTerminate(_ notification: Notification) {
        contentAutoRefreshTimer?.invalidate()
        presenterTimer.pauseTimer()
        presentationCoordinator?.shutdown()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }
        NSApp.terminate(self)
    }

}
