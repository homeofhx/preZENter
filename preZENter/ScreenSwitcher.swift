import Cocoa

class ScreenSwitcher: NSObject {
    
    public func getScreenNameOrResolution(screen: NSScreen) -> String {
        guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return "External Screen"
        }
        
        if CGDisplayIsBuiltin(screenID) != 0 {
            return "Mac's Built-in Display"
        }
        
        var ioIterator: io_iterator_t = 0
        let services = IOServiceMatching("IODisplayConnect")
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, services, &ioIterator)
        
        if result == kIOReturnSuccess {
            var service = IOIteratorNext(ioIterator)
            while service != 0 {
                if let info = IODisplayCreateInfoDictionary(service, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any] {
                    let vendor = info[kDisplayVendorID] as? UInt32
                    let product = info[kDisplayProductID] as? UInt32
                    /// Using to prevent potential errors on Xcode 10
                    let screenVendor = screen.deviceDescription[NSDeviceDescriptionKey("CGDisplayVendorNumber")] as? UInt32
                    let screenProduct = screen.deviceDescription[NSDeviceDescriptionKey("CGDisplayProductID")] as? UInt32
                    
                    if vendor == screenVendor && product == screenProduct {
                        if let names = info[kDisplayProductName] as? [String: Any],
                            let screenName = names.values.first as? String {
                            IOObjectRelease(service)
                            IOObjectRelease(ioIterator)
                            return screenName
                        }
                    }
                }
                
                service = IOIteratorNext(ioIterator)
            }
        }
        
        return "Screen (\(Int(screen.frame.width))x\(Int(screen.frame.height)))"
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
