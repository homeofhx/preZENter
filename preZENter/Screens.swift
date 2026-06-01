import Cocoa
import CoreGraphics

class Screens: NSObject {
    
    private var currentDisplayID: CGDirectDisplayID?
    private var captureTimer: Timer?
    
    public func getItems() -> [(title: String, displayID: CGDirectDisplayID)] {
        var result: [(title: String, displayID: CGDirectDisplayID)] = []
        
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            
            /// NOTE: comment out the following if-statement when building on Xcode 10, or it won't build.
//            if #available(macOS 10.15, *) {
//                result.append((title: screen.localizedName, displayID: displayID))
//                continue
//            }
            
            let screenSize = screen.frame.size
            let screenName = "Screen: \(Int(screenSize.width)) x \(Int(screenSize.height))"
            result.append((title: screenName, displayID: displayID))
        }
        
        return result
    }
    
    public func selectScreen(displayID: CGDirectDisplayID, liveWindow: LiveWindow) {
        stopScreenSession(liveWindow: liveWindow)
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
        guard let imageRef = CGDisplayCreateImage(displayID) else { return nil }
        return NSImage(cgImage: imageRef, size: NSZeroSize)
    }
    
    private func showScreenLiveView(liveWindow: LiveWindow) {
        captureTimer?.invalidate()
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let displayID = self.currentDisplayID,
                  let screenImage = self.captureScreenImage(displayID: displayID)
            else { return }
            
            DispatchQueue.main.async {
                liveWindow.updateWindowLayerImage(screenImage)
            }
        }
    }
    
}
