import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var windowsList: NSPopUpButton!
    @IBOutlet weak var devList: NSPopUpButton!
    @IBOutlet weak var liveContentIndicator: NSTextField!
    @IBOutlet weak var timerText: NSTextField!
    @IBOutlet weak var timerButtonLabel: NSTextField!
    
    private var liveWindow: LiveWindow?
    private var videoDevs = VideoCaptureDevs()
    private var windows = Windows()
    private let presenterTimer = PresenterTimer()
    private var isTimerRunning: Bool = false
    
    @IBAction func getRelease(_ sender: AnyObject) {
        let url = URL(string: "https://github.com/homeofhx/preZENter/releases/latest")
        NSWorkspace.shared.open(url!)
    }
    
    @IBAction func getHelp(_ sender: Any) {
        let url = URL(string: "https://github.com/homeofhx/preZENter/wiki")
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
    
    @IBAction func refresh(_ sender: Any) {
        windows.refreshWindows(popup: windowsList)
        videoDevs.refreshDevs(popup: devList)
    }
    
    @IBAction func timerButton(_ sender: Any) {
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
    
    private func setup(list: NSPopUpButton) {
        if liveWindow == nil {
            liveWindow = LiveWindow()
        }
        
        if list.selectedItem?.title == "-- None --" {
            liveContentIndicator.stringValue = "Nothing"
        } else {
            liveContentIndicator.stringValue = list.selectedItem?.title ?? ""
        }
    }
    
    private func setupTimer() {
        presenterTimer.onTick = {[weak self] timeString in DispatchQueue.main.async {
                self?.timerText.stringValue = timeString
            }
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if #available(macOS 10.15, *) {
//            CGRequestScreenCaptureAccess()     // NOTE: uncomment this part when building on Xcode 10, or it won't build
        }
        
        windowsList.addItem(withTitle: "-- None --")
        devList.addItem(withTitle: "-- None --")
        windows.setup(popup: windowsList)
        videoDevs.setup(popup: devList)
        setupTimer()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
    }
    
}
