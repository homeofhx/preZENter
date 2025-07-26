import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var windowsList: NSPopUpButton!
    @IBOutlet weak var devList: NSPopUpButton!
    @IBOutlet weak var liveContent: NSTextField!
    
    private var liveWindow: LiveWindow?
    private var videoDevs = VideoCaptureDevs()
    private var windows = Windows()
    
    @IBAction func selectWindow(_ sender: Any) {
        if liveWindow == nil {
            liveWindow = LiveWindow()
        }
        
        videoDevs.stopVideoDevSession(liveWindow: liveWindow!)
        liveContent.stringValue = windowsList.selectedItem?.title ?? ""
        windows.selectWindow(popup: windowsList, liveWindow: liveWindow!)
    }
    
    @IBAction func refreshWindows(_ sender: Any) {
        windows.refreshWindows(popup: windowsList)
    }
    
    @IBAction func selectVideoDev(_ sender: Any) {
        if liveWindow == nil {
            liveWindow = LiveWindow()
        }
        
        windows.stopWindowSession(liveWindow: liveWindow!)
        liveContent.stringValue = devList.selectedItem?.title ?? ""
        videoDevs.selectDev(popup: devList, liveWindow: liveWindow!)
    }
    
    @IBAction func refreshVideoDevs(_ sender: Any) {
        videoDevs.refreshDevs(popup: devList)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()     // NOTE: uncomment this part when building on Xcode 10, or it won't build
        }
        
        windowsList.addItem(withTitle: "-- Select an app's window --")
        devList.addItem(withTitle: "-- Select a video capture device --")
        windows.setup(popup: windowsList)
        videoDevs.setup(popup: devList)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
    }
    
}
