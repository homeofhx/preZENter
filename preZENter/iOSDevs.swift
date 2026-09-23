import Cocoa

final class iOSDevs {
    
    public var onDeviceLost: (() -> Void)?
    
    private lazy var captureSession: CaptureDevSession = {
        let session = CaptureDevSession(queueLabel: "com.prezenter.iosDevices.sessionQueue")
        session.onDeviceLost = { [weak self] in self?.onDeviceLost?() }
        return session
    }()
    
    func selectDevice(uniqueID: String, liveWindow: LiveWindow) {
        captureSession.selectDevice(uniqueID: uniqueID, liveWindow: liveWindow)
    }
    
    func pausePresentation(liveWindow: LiveWindow) {
        captureSession.pausePresentation(liveWindow: liveWindow)
    }
    
    func stopSession(liveWindow: LiveWindow) {
        captureSession.stopSession(liveWindow: liveWindow)
    }
    
}
