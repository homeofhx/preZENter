import Cocoa
import CoreAudio

class Switchers: NSObject {
    
    /// Below is thw Screen Switcher
    
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
    
    
    
    /// Below is the Audio Switcher
    /// Note for mElement: use kAudioObjectPropertyElementMaster for Xcode 10, kAudioObjectPropertyElementMain for latest Xcode
    
    public func getAudioOutputDeviceName(deviceID: AudioDeviceID) -> String {
        var name: CFString = "" as CFString
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)
        
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &name)
        return (name as String)
    }
    
    public func getAudioOutputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)
        
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var audioDeviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &audioDeviceIDs)
        
        return audioDeviceIDs.filter { id in
            var outputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMaster)
            var outputSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &outputSize)
            return outputSize > 0
        }
    }
    
    public func setAudioOutputDevice(to deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)
        var deviceIDCopy = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.stride)
        
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &deviceIDCopy)
    }
}
