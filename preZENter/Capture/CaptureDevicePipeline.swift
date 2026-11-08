import Cocoa
import AVFoundation

enum CapturePreviewChannel: Equatable {
    case videoDevice
    case iOSDevice
}

final class CaptureDevicePipeline {

    struct Activation: Equatable {
        let uniqueID: String
        let presentationID: UInt64
    }

    var onDeviceLost: ((Activation) -> Void)?

    private let channel: CapturePreviewChannel
    private let sessionQueue: DispatchQueue
    private let stateLock = NSLock()
    private var requestedActivation: Activation?

    private var currentDevice: AVCaptureDevice?
    private var currentSession: AVCaptureSession?
    private var audioPreviewOutput: AVCaptureAudioPreviewOutput?

    init(channel: CapturePreviewChannel, queueLabel: String) {
        self.channel = channel
        sessionQueue = DispatchQueue(label: queueLabel)
    }

    func activate(uniqueID: String, presentationID: UInt64, liveWindow: LiveWindow) {
        let activation = Activation(uniqueID: uniqueID, presentationID: presentationID)
        setRequestedActivation(activation)

        sessionQueue.async { [weak self, weak liveWindow] in
            guard let self = self, let liveWindow = liveWindow else { return }

            if let session = self.currentSession,
               self.currentDevice?.uniqueID == uniqueID {
                self.audioPreviewOutput?.volume = 1.0
                self.present(session, activation: activation, liveWindow: liveWindow)
                return
            }

            self.teardownCurrentSession()
            guard self.isRequested(activation) else { return }
            guard let device = AVCaptureDevice(uniqueID: uniqueID) else {
                self.reportDeviceLost(activation)
                return
            }
            self.buildAndStartSession(device: device, activation: activation, liveWindow: liveWindow)
        }
    }

    func deactivate(liveWindow: LiveWindow) {
        let oldActivation = replaceRequestedActivation(with: nil)
        guard let activation = oldActivation else { return }

        sessionQueue.async { [weak self, weak liveWindow] in
            guard let self = self else { return }
            self.audioPreviewOutput?.volume = 0
            guard let session = self.currentSession else { return }
            DispatchQueue.main.async {
                liveWindow?.hideCapturePreview(session: session, channel: self.channel, presentationID: activation.presentationID)
            }
        }
    }

    func shutdown(liveWindow: LiveWindow) {
        setRequestedActivation(nil)
        sessionQueue.async { [weak self, weak liveWindow] in
            guard let self = self else { return }
            if let session = self.currentSession {
                DispatchQueue.main.async { liveWindow?.detachCapturePreview(session: session, channel: self.channel) }
            }
            self.teardownCurrentSession()
        }
    }

    private func buildAndStartSession(device: AVCaptureDevice, activation: Activation, liveWindow: LiveWindow) {
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            reportDeviceLost(activation)
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            reportDeviceLost(activation)
            return
        }
        session.addInput(input)

        if !device.hasMediaType(.muxed),
           let audioDevice = CaptureDeviceDiscovery.matchingAudioDevice(for: device),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        let audioPreview = AVCaptureAudioPreviewOutput()
        audioPreview.volume = 1.0
        if session.canAddOutput(audioPreview) { session.addOutput(audioPreview) }
        if device.supportsSessionPreset(.high) { session.sessionPreset = .high }
        session.commitConfiguration()

        guard isRequested(activation) else {
            teardown(session: session)
            return
        }

        currentDevice = device
        currentSession = session
        audioPreviewOutput = audioPreview
        session.startRunning()

        guard isRequested(activation) else {
            audioPreview.volume = 0
            return
        }

        present(session, activation: activation, liveWindow: liveWindow)
    }

    private func present(_ session: AVCaptureSession, activation: Activation, liveWindow: LiveWindow) {
        DispatchQueue.main.async { [weak self, weak liveWindow] in
            guard let self = self, self.isRequested(activation) else { return }
            liveWindow?.showCapturePreview(session: session, channel: self.channel, presentationID: activation.presentationID)
        }
    }

    private func reportDeviceLost(_ activation: Activation) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRequested(activation) else { return }
            self.setRequestedActivation(nil)
            self.onDeviceLost?(activation)
        }
    }

    private func teardownCurrentSession() {
        currentDevice = nil
        audioPreviewOutput = nil
        guard let session = currentSession else { return }
        currentSession = nil
        teardown(session: session)
    }

    private func teardown(session: AVCaptureSession) {
        session.stopRunning()
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
    }

    private func setRequestedActivation(_ activation: Activation?) {
        stateLock.lock()
        requestedActivation = activation
        stateLock.unlock()
    }

    private func replaceRequestedActivation(with activation: Activation?) -> Activation? {
        stateLock.lock()
        let oldActivation = requestedActivation
        requestedActivation = activation
        stateLock.unlock()
        return oldActivation
    }

    private func isRequested(_ activation: Activation) -> Bool {
        stateLock.lock()
        let isCurrent = requestedActivation == activation
        stateLock.unlock()
        return isCurrent
    }

}
