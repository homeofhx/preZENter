import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var windowsList: NSPopUpButton!
    @IBOutlet weak var devList: NSPopUpButton!
    @IBOutlet weak var liveContentIndicator: NSTextField!
    
    private var liveWindow: LiveWindow?
    private var videoDevs = VideoCaptureDevs()
    private var windows = Windows()
    
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
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if #available(macOS 10.15, *) {
//            CGRequestScreenCaptureAccess()     // NOTE: uncomment this part when building on Xcode 10, or it won't build
        }
        
        windowsList.addItem(withTitle: "-- None --")
        devList.addItem(withTitle: "-- None --")
        windows.setup(popup: windowsList)
        videoDevs.setup(popup: devList)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
    }
    
}
