import Cocoa
import CoreAudio

final class SystemSwitcher {
    private var displayMoveID: UInt64 = 0
    
    // MARK: - Display Switcher
    
    func displayName(for screen: NSScreen) -> String {
        guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return "External Display" }
        if #available(macOS 10.15, *) { return screen.localizedName }
        if CGDisplayIsBuiltin(screenID) != 0 { return "Mac's Built-in Display" }
        return "Screen: (\(Int(screen.frame.width * screen.backingScaleFactor))x\(Int(screen.frame.height * screen.backingScaleFactor)))"
    }
    
    func moveLiveWindow(_ window: NSWindow, toScreenAt index: Int) {
        let screens = NSScreen.screens
        guard screens.indices.contains(index) else { return }
        displayMoveID &+= 1
        let currentMoveID = displayMoveID
        let targetScreen = screens[index]
        
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self, weak window] in
                guard let self = self,
                      self.displayMoveID == currentMoveID,
                      let window = window else { return }
                self.moveLiveWindowThenToggleFullScreen(window: window, screen: targetScreen)
            }
        } else {
            moveLiveWindowThenToggleFullScreen(window: window, screen: targetScreen)
        }
    }
    
    private func moveLiveWindowThenToggleFullScreen(window: NSWindow, screen: NSScreen) {
        window.setFrameOrigin(screen.frame.origin)
        window.toggleFullScreen(nil)
    }
    
    // MARK: - Audio Switcher
    
    func audioOutputDeviceName(deviceID: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>? = nil
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString,
                                                         mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &name)
        if status == noErr, let unmanagedName = name { return unmanagedName.takeRetainedValue() as String }
        
        return "Unknown Audio Device"
    }
    
    func audioOutputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var audioDeviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &audioDeviceIDs)
        
        return audioDeviceIDs.filter { id in
            var outputAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                           mScope: kAudioDevicePropertyScopeOutput,
                                                           mElement: kAudioObjectPropertyElementMaster)
            var outputSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &outputSize)
            return outputSize > 0
        }
    }
    
    func setAudioOutputDevice(_ deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMaster)
        var deviceIDCopy = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.stride)
        
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &deviceIDCopy)
    }
    
}
