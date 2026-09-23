import Cocoa
import AVFoundation

final class CaptureDevSession {
    
    public var onDeviceLost: (() -> Void)?
    
    private var currentDevice: AVCaptureDevice?
    private var currentSession: AVCaptureSession?
    private var audioPreviewOutput: AVCaptureAudioPreviewOutput?
    private var requestedUniqueID: String?
    
    private let stateLock = NSLock()
    private let sessionQueue: DispatchQueue
    
    init(queueLabel: String) {
        sessionQueue = DispatchQueue(label: queueLabel)
    }
    
    func selectDevice(uniqueID: String, liveWindow: LiveWindow) {
        setRequestedUniqueID(uniqueID)
        
        sessionQueue.async { [weak self, weak liveWindow] in
            guard let self = self, let liveWindow = liveWindow else { return }
            
            if let session = self.currentSession,
               self.currentDevice?.uniqueID == uniqueID {
                self.resumeExistingSession(session, uniqueID: uniqueID, liveWindow: liveWindow)
                return
            }
            
            self.teardownCurrentSession()
            guard self.isRequested(uniqueID) else { return }
            guard let device = AVCaptureDevice(uniqueID: uniqueID) else {
                self.reportDeviceLost(ifRequested: uniqueID)
                return
            }
            
            self.buildAndStartSession(device: device, uniqueID: uniqueID, liveWindow: liveWindow)
        }
    }
    
    func pausePresentation(liveWindow: LiveWindow) {
        setRequestedUniqueID(nil)
        
        sessionQueue.async { [weak self, weak liveWindow] in
            guard let self = self else { return }
            self.audioPreviewOutput?.volume = 0
            guard let session = self.currentSession else { return }
            DispatchQueue.main.async { liveWindow?.hideCapturePreview(session: session) }
        }
    }
    
    func stopSession(liveWindow: LiveWindow) {
        setRequestedUniqueID(nil)
        
        sessionQueue.async { [weak self, weak liveWindow] in
            guard let self = self else { return }
            if let session = self.currentSession {
                DispatchQueue.main.async { liveWindow?.stopCapturePreview(session: session) }
            }
            
            self.teardownCurrentSession()
        }
    }
    
    private func teardownCurrentSession() {
        currentDevice = nil
        audioPreviewOutput = nil
        guard let session = currentSession else { return }
        session.stopRunning()
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        currentSession = nil
    }
    
    private func resumeExistingSession(_ session: AVCaptureSession, uniqueID: String, liveWindow: LiveWindow) {
        audioPreviewOutput?.volume = 1.0
        present(session, ifRequested: uniqueID, liveWindow: liveWindow)
    }
    
    private func buildAndStartSession(device: AVCaptureDevice, uniqueID: String, liveWindow: LiveWindow) {
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            reportDeviceLost(ifRequested: uniqueID)
            return
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            reportDeviceLost(ifRequested: uniqueID)
            return
        }
        
        session.addInput(input)
        
        if !device.hasMediaType(.muxed),
           let audioDevice = CaptureDevDiscovery.matchingAudioDevice(for: device),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        let audioPreview = AVCaptureAudioPreviewOutput()
        audioPreview.volume = 1.0
        if session.canAddOutput(audioPreview) { session.addOutput(audioPreview) }
        if device.supportsSessionPreset(.high) { session.sessionPreset = .high }
        session.commitConfiguration()
        
        guard isRequested(uniqueID) else { return }
        
        session.startRunning()
        currentDevice = device
        currentSession = session
        audioPreviewOutput = audioPreview
        present(session, ifRequested: uniqueID, liveWindow: liveWindow)
    }
    
    private func present(_ session: AVCaptureSession, ifRequested uniqueID: String, liveWindow: LiveWindow) {
        DispatchQueue.main.async { [weak self, weak liveWindow] in
            guard let self = self,
                  self.isRequested(uniqueID) else { return }
            liveWindow?.showCapturePreview(session: session)
        }
    }
    
    private func reportDeviceLost(ifRequested uniqueID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isRequested(uniqueID) else { return }
            self.setRequestedUniqueID(nil)
            self.onDeviceLost?()
        }
    }
    
    private func setRequestedUniqueID(_ uniqueID: String?) {
        stateLock.lock()
        requestedUniqueID = uniqueID
        stateLock.unlock()
    }
    
    private func isRequested(_ uniqueID: String) -> Bool {
        stateLock.lock()
        let result = requestedUniqueID == uniqueID
        stateLock.unlock()
        return result
    }
    
}
