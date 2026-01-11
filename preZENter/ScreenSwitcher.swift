import Cocoa

class ScreenSwitcher: NSObject {
    
    public func getScreenNameOrResolution(screen: NSScreen) -> String {
        guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return "External Screen"
        }
        
        /// NOTE: comment out the following if-statement when building on Xcode 10, or it won't build.
//        if #available(macOS 10.15, *) {
//            return screen.localizedName
//        }
        
        if CGDisplayIsBuiltin(screenID) != 0 {
            return "Mac's Built-in Display"
        }
        
        return "Screen (\(Int(screen.frame.width * screen.backingScaleFactor))x\(Int(screen.frame.height * screen.backingScaleFactor)))"
    }
    
    public func moveLiveWindowToSelectedScreen(window: NSWindow, to index: Int) {
        let screens = NSScreen.screens
        guard index < screens.count else { return }
        let targetScreen = screens[index]
        
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak window] in
                if let win = window {
                    self.moveLiveWindowThenToggleFullScreen(window: win, screen: targetScreen)
                }
            }
        } else {
            moveLiveWindowThenToggleFullScreen(window: window, screen: targetScreen)
        }
    }
    
    private func moveLiveWindowThenToggleFullScreen(window: NSWindow, screen: NSScreen) {
        window.setFrameOrigin(screen.frame.origin)
        window.toggleFullScreen(nil)
    }
    
}
