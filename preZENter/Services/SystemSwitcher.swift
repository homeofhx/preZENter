import Cocoa
import CoreAudio

final class SystemSwitcher {
    private static let screenConfirmationDelay: TimeInterval = 0.05
    private static let screenSettlingDelay: TimeInterval = 0.15
    private static let maximumScreenConfirmationAttempts = 40
    
    private var displayMoveID: UInt64 = 0
    private var fullScreenExitObserver: NSObjectProtocol?
    
    deinit {
        removeFullScreenExitObserver()
    }
    
    // MARK: - Display Switcher
    
    func displayName(for screen: NSScreen) -> String {
        guard let screenID = screen.displayID else { return "External Display" }
        if #available(macOS 10.15, *) { return screen.localizedName }
        if CGDisplayIsBuiltin(screenID) != 0 { return "Mac's Built-in Display" }
        return "Screen: (\(Int(screen.frame.width * screen.backingScaleFactor))x\(Int(screen.frame.height * screen.backingScaleFactor)))"
    }
    
    func moveLiveWindow(_ window: NSWindow, toScreenAt index: Int) {
        let screens = NSScreen.screens
        guard screens.indices.contains(index) else { return }
        moveLiveWindow(window, to: screens[index])
    }
    
    func moveLiveWindow(_ window: NSWindow, to screen: NSScreen) {
        moveLiveWindowToFullScreen(window, to: screen)
    }
    
    func moveLiveWindowToFullScreen(_ window: NSWindow, to screen: NSScreen) {
        displayMoveID &+= 1
        let currentMoveID = displayMoveID
        removeFullScreenExitObserver()
        
        guard let targetDisplayID = screen.displayID else { return }
        if window.styleMask.contains(.fullScreen), window.screen?.displayID == targetDisplayID { return }
        
        if window.styleMask.contains(.fullScreen) {
            fullScreenExitObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main) { [weak self, weak window] _ in
                    guard let self = self else { return }
                    self.removeFullScreenExitObserver()
                    guard self.displayMoveID == currentMoveID,
                          let window = window else { return }
                    DispatchQueue.main.async { [weak self, weak window] in
                        guard let self = self,
                              self.displayMoveID == currentMoveID,
                              let window = window else { return }
                        self.moveThenEnterFullScreen(window: window,
                                                     screen: screen,
                                                     targetDisplayID: targetDisplayID,
                                                     moveID: currentMoveID)
                    }
            }
            window.toggleFullScreen(nil)
        } else {
            moveThenEnterFullScreen(window: window,
                                    screen: screen,
                                    targetDisplayID: targetDisplayID,
                                    moveID: currentMoveID)
        }
    }
    
    private func moveThenEnterFullScreen(window: NSWindow,
                                         screen: NSScreen,
                                         targetDisplayID: CGDirectDisplayID,
                                         moveID: UInt64) {
        let targetFrame = screen.visibleFrame
        let origin = NSPoint(x: targetFrame.midX - window.frame.width / 2, y: targetFrame.midY - window.frame.height / 2)
        window.setFrameOrigin(origin)
        waitForTargetScreen(window: window,
                            targetDisplayID: targetDisplayID,
                            moveID: moveID,
                            attemptsRemaining: SystemSwitcher.maximumScreenConfirmationAttempts)
    }
    
    private func waitForTargetScreen(window: NSWindow,
                                     targetDisplayID: CGDirectDisplayID,
                                     moveID: UInt64,
                                     attemptsRemaining: Int) {
        guard displayMoveID == moveID,
              !window.styleMask.contains(.fullScreen) else { return }
        
        if window.screen?.displayID == targetDisplayID {
            DispatchQueue.main.asyncAfter(deadline: .now() + SystemSwitcher.screenSettlingDelay) {
                [weak self, weak window] in
                guard let self = self,
                      self.displayMoveID == moveID,
                      let window = window,
                      window.screen?.displayID == targetDisplayID,
                      !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
            return
        }
        
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + SystemSwitcher.screenConfirmationDelay) {
            [weak self, weak window] in
            guard let self = self,
                  self.displayMoveID == moveID,
                  let window = window else { return }
            self.waitForTargetScreen(window: window,
                                     targetDisplayID: targetDisplayID,
                                     moveID: moveID,
                                     attemptsRemaining: attemptsRemaining - 1)
        }
    }
    
    private func removeFullScreenExitObserver() {
        guard let observer = fullScreenExitObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        fullScreenExitObserver = nil
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
