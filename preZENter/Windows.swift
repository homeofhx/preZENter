import Cocoa
import CoreGraphics

class Windows: NSObject {
    
    private var currentWindowID: CGWindowID?
    private let minWindowBound: CGFloat = 125
    private var captureTimer: Timer?
    
    public func getItems() -> [(title: String, windowID: CGWindowID)] {
        var result: [(title: String, windowID: CGWindowID)] = []
        
        let listInfo = CGWindowListCopyWindowInfo(CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly), kCGNullWindowID)
        
        guard let windowList = listInfo as? [[String: AnyObject]] else { return result }
        
        for window in windowList {
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            guard let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard bounds.width >= minWindowBound, bounds.height >= minWindowBound else { continue }
            guard let content = window[kCGWindowName as String] as? String, !content.isEmpty else { continue }
            guard let appName = window[kCGWindowOwnerName as String] as? String, appName != "preZENter" else { continue }
            guard let windowNum = window[kCGWindowNumber as String] as? NSNumber else { continue }
            
            result.append((title: "\(appName): \(content)", windowID: windowNum.uint32Value))
        }
        
        return result
    }
    
    public func selectWindow(id: CGWindowID, liveWindow: LiveWindow) {
        stopWindowSession(liveWindow: liveWindow)
        currentWindowID = id
        showCurrentWindowLiveView(liveWindow: liveWindow)
    }
    
    public func stopWindowSession(liveWindow: LiveWindow) {
        captureTimer?.invalidate()
        captureTimer = nil
        currentWindowID = nil
        liveWindow.stopLiveView()
    }
    
    private func captureWindowImage(windowID: CGWindowID) -> NSImage? {
        guard let ref = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.bestResolution, .boundsIgnoreFraming]) else { return nil }
        return NSImage(cgImage: ref, size: NSZeroSize)
    }
    
    private func showCurrentWindowLiveView(liveWindow: LiveWindow) {
        captureTimer?.invalidate()
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let windowID = self.currentWindowID,
                let windowImage = self.captureWindowImage(windowID: windowID)
                else {
                    self.stopWindowSession(liveWindow: liveWindow)
                    return
            }
            
            liveWindow.updateWindowLayerImage(windowImage)
        }
    }
    
}
