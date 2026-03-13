import Cocoa
import CoreGraphics

class Screens: NSObject {
    
    private var currentDisplayID: CGDirectDisplayID?
    private var captureTimer: Timer?
    
    public func setup(popup: NSPopUpButton) {
        popup.addItem(withTitle: "-- None --")

        for screen in NSScreen.screens {
            let description = screen.deviceDescription
            if let displayID = description[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                let screenName: String
                /// NOTE: comment out the following if-statement when building on Xcode 10, or it won't build.
//                if #available(macOS 10.15, *) {
//                    screenName = screen.localizedName
//                } else {
                    let size = screen.frame.size
                    screenName = "Screen \(Int(size.width))x\(Int(size.height))"
//                }
                
                popup.addItem(withTitle: screenName)
                popup.lastItem?.representedObject = displayID
            }
        }
    }
    
    public func refreshScreens(popup: NSPopUpButton) {
        while popup.numberOfItems > 1 {
            popup.removeItem(at: 1)
        }
        
        setup(popup: popup)
    }
    
    public func selectScreen(popup: NSPopUpButton, liveWindow: LiveWindow) {
        stopScreenSession(liveWindow: liveWindow)
        
        guard let selectedScreen = popup.selectedItem,
            let displayID = selectedScreen.representedObject as? CGDirectDisplayID else { return }
        
        currentDisplayID = displayID
        showScreenLiveView(liveWindow: liveWindow)
    }
    
    public func stopScreenSession(liveWindow: LiveWindow) {
        captureTimer?.invalidate()
        captureTimer = nil
        currentDisplayID = nil
        liveWindow.stopLiveView()
    }
    
    private func captureScreenImage(displayID: CGDirectDisplayID) -> NSImage? {
        if let imageRef = CGDisplayCreateImage(displayID) {
            return NSImage(cgImage: imageRef, size: NSZeroSize)
        }
        
        return nil
    }
    
    private func showScreenLiveView(liveWindow: LiveWindow) {
        captureTimer?.invalidate()
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in
            guard let self = self,
                let displayID = self.currentDisplayID,
                let screenImage = self.captureScreenImage(displayID: displayID) else {
                    return
            }
            
            DispatchQueue.main.async {
                liveWindow.updateWindowLayerImage(screenImage)
            }
        }
    }
    
}
