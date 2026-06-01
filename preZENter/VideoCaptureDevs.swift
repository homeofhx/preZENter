import Cocoa
import AVFoundation
import CoreMediaIO

class VideoCaptureDevs: NSObject {
    
    private var videoDevices: [AVCaptureDevice] = []
    private var currentDevice: AVCaptureDevice?
    private var currentSession = AVCaptureSession()
    
    override init() {
        super.init()
        VideoCaptureDevs.unlockiOSScreenCapture()
        videoDevices = enumerateAllVideoDevs()
    }
    
    public func getDeviceNames() -> [String] {
        VideoCaptureDevs.unlockiOSScreenCapture()
        videoDevices = enumerateAllVideoDevs()
        return videoDevices.map { $0.localizedName }
    }
    
    public func selectDev(at index: Int, liveWindow: LiveWindow) {
        stopVideoDevSession(liveWindow: liveWindow)
        
        for input in currentSession.inputs {
            currentSession.removeInput(input)
        }
        
        guard index >= 0, index < videoDevices.count else { return }
        currentDevice = videoDevices[index]
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
        return (videoDevs + muxedDevs).filter { seen.insert($0.uniqueID).inserted }
    }
    
}
