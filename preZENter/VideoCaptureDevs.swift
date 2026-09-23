import Cocoa

final class VideoCaptureDevs {
    
    public var onVideoDevLost: (() -> Void)?
    
    private lazy var captureSession: CaptureDevSession = {
        let session = CaptureDevSession(queueLabel: "com.prezenter.videoCaptureDevs.sessionQueue")
        session.onDeviceLost = { [weak self] in self?.onVideoDevLost?() }
        return session
    }()
    
    func selectVideoDev(uniqueID: String, liveWindow: LiveWindow) {
        captureSession.selectDevice(uniqueID: uniqueID, liveWindow: liveWindow)
    }
    
    func pauseVideoDevPresentation(liveWindow: LiveWindow) {
        captureSession.pausePresentation(liveWindow: liveWindow)
    }
    
    func stopVideoDevSession(liveWindow: LiveWindow) {
        captureSession.stopSession(liveWindow: liveWindow)
    }
    
}
