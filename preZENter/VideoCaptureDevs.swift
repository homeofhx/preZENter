import Cocoa
import AVFoundation
import CoreMediaIO

class VideoCaptureDevs: NSObject {
    
    public var onVideoDevLost: (() -> Void)?
    
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
    
    public func selectVideoDev(at index: Int, liveWindow: LiveWindow) {
        stopVideoDevSession(liveWindow: liveWindow)
        currentSession.inputs.forEach { currentSession.removeInput($0) }
        
        guard index >= 0, index < videoDevices.count else {
            DispatchQueue.main.async { self.onVideoDevLost?() }
            return
        }
        
        currentDevice = videoDevices[index]
        showLiveView(liveWindow: liveWindow)
    }
    
    public func stopVideoDevSession(liveWindow: LiveWindow) {
        currentSession.stopRunning()
        liveWindow.stopLiveView()
    }
    
    private func showLiveView(liveWindow: LiveWindow) {
        guard let device = currentDevice else {
            DispatchQueue.main.async { self.onVideoDevLost?() }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            guard currentSession.canAddInput(input) else {
                DispatchQueue.main.async { self.onVideoDevLost?() }
                return
            }
            
            currentSession.addInput(input)
        } catch {
            DispatchQueue.main.async { self.onVideoDevLost?() }
            return
        }
        
        currentSession.sessionPreset = .high
        currentSession.startRunning()
        liveWindow.setupLiveView(session: currentSession)
    }
    
    private static func unlockiOSScreenCapture() {
        var prop = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
        var allow: UInt32 = 1
        
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                  &prop, 0, nil,
                                  UInt32(MemoryLayout<UInt32>.size),
                                  &allow)
    }
    
    private func enumerateAllVideoDevs() -> [AVCaptureDevice] {
        var seen = Set<String>()
        return (AVCaptureDevice.devices(for: .video) + AVCaptureDevice.devices(for: .muxed))
            .filter { seen.insert($0.uniqueID).inserted }
    }
    
}
