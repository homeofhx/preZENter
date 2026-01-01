import Cocoa
import CoreGraphics

class Windows: NSObject {
    
    private var currentWindowID: CGWindowID?
    private let minWindowBound: CGFloat = 125
    
    public func setup(popup: NSPopUpButton) {
        let windowsListInfo = CGWindowListCopyWindowInfo(CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly), kCGNullWindowID)
        
        if let windowList = windowsListInfo as? [[String: AnyObject]] {
            for window in windowList {
                let windowBounds = window[kCGWindowBounds as String] as? [String: CGFloat]
                let windowBoundsAsRectangle = CGRect(dictionaryRepresentation: windowBounds! as CFDictionary)
                let width = windowBoundsAsRectangle!.width
                let height = windowBoundsAsRectangle!.height
                
                if let appContent = window[kCGWindowName as String] as? String,
                    let appName = window[kCGWindowOwnerName as String] as? String,
                    let windowID = window[kCGWindowNumber as String] as? NSNumber,
                    appContent.count != 0, appName != "preZENter",
                    width >= minWindowBound, height >= minWindowBound {
                    popup.addItem(withTitle: "\(appName): \(appContent)")
                    popup.lastItem?.representedObject = windowID.uint32Value
                }
            }
        }
    }
    
    public func refreshWindows(popup: NSPopUpButton) {
        while popup.numberOfItems > 1 {
            popup.removeItem(at: 1)
        }
        
        setup(popup: popup)
    }
    
    public func selectWindow(popup: NSPopUpButton, liveWindow: LiveWindow) {
        stopWindowSession(liveWindow: liveWindow)
        
        guard let selectedWindow = popup.selectedItem,
            let windowID = selectedWindow.representedObject as? CGWindowID else {
                return
        }
        
        currentWindowID = windowID
        showLiveView(liveWindow: liveWindow)
    }
    
    public func stopWindowSession(liveWindow: LiveWindow) {
        currentWindowID = nil
        liveWindow.stopLiveView()
    }
    
    private func captureWindowImage(windowID: CGWindowID) -> NSImage? {
        let imageRef = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.bestResolution, .boundsIgnoreFraming])
        
        if let windowImage = imageRef {
            return NSImage(cgImage: windowImage, size: NSZeroSize)
        }
        
        return nil
    }
    
    private func showLiveView(liveWindow: LiveWindow) {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            guard let image = self.captureWindowImage(windowID: self.currentWindowID ?? kCGNullWindowID) else {
                timer.invalidate()
                return
            }
            
            liveWindow.updateImage(image)
        }
    }
    
}
