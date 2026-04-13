import Cocoa
import AVFoundation
import CoreMediaIO

class VideoCaptureDevs: NSObject {
    
    private var videoDevices: [AVCaptureDevice] = []
    private var currentDevice: AVCaptureDevice!
    private var currentSession = AVCaptureSession()
    
    override init() {
        super.init()
        VideoCaptureDevs.unlockiOSScreenCapture()
    }
    
    public func setup(popup: NSPopUpButton) {
        videoDevices = enumerateAllVideoDevs()
        popup.addItem(withTitle: "-- None --")
        
        for device in videoDevices {
            popup.addItem(withTitle: device.localizedName)
        }
    }
    
    public func refreshDevs(popup: NSPopUpButton) {
        while popup.numberOfItems > 1 {
            popup.removeItem(at: 1)
        }
        
        VideoCaptureDevs.unlockiOSScreenCapture()
        videoDevices = enumerateAllVideoDevs()
        popup.addItem(withTitle: "-- None --")
        for device in videoDevices {
            popup.addItem(withTitle: device.localizedName)
        }
    }
    
    public func selectDev(popup: NSPopUpButton, liveWindow: LiveWindow) {
        stopVideoDevSession(liveWindow: liveWindow)
        
        for input in currentSession.inputs {
            currentSession.removeInput(input)
        }
        
        let selectedIndex = popup.indexOfSelectedItem - 1
        guard selectedIndex >= 0, selectedIndex < videoDevices.count else { return }
        
        currentDevice = videoDevices[selectedIndex]
        showLiveView(liveWindow: liveWindow)
    }
    
    public func stopVideoDevSession(liveWindow: LiveWindow) {
        currentSession.stopRunning()
        liveWindow.stopLiveView()
    }
    
    private func showLiveView(liveWindow: LiveWindow) {
        guard let device = currentDevice else { return }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard currentSession.canAddInput(input) else { return }
            currentSession.addInput(input)
        } catch { return }
        
        currentSession.sessionPreset = .high
        currentSession.startRunning()
        liveWindow.setupLiveView(session: currentSession)
    }
    
    private static func unlockiOSScreenCapture() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
    }
    
    private func enumerateAllVideoDevs() -> [AVCaptureDevice] {
        let videoDevs = AVCaptureDevice.devices(for: .video)
        let muxedDevs = AVCaptureDevice.devices(for: .muxed)
        var seen = Set<String>()
        return (videoDevs + muxedDevs).filter{seen.insert($0.uniqueID).inserted}
    }
    
}
