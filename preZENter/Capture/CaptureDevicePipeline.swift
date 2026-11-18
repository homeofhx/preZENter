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
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var monoAudioPreview: MonoAudioPreview?
    private var outputVolume: Float = 1
    private var isAudioMuted = false
    private var usesMonoAudioOutput = false

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
                self.applyAudioOutput(isActive: true)
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
            self.applyAudioOutput(isActive: false)
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

    func updateAudioConfiguration(volume: Float, isMuted: Bool, usesMonoOutput: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.outputVolume = max(0, min(volume, 1))
            self.isAudioMuted = isMuted
            self.usesMonoAudioOutput = usesMonoOutput
            self.applyAudioOutput(isActive: self.hasRequestedActivation())
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
        audioPreview.volume = 0
        if session.canAddOutput(audioPreview) { session.addOutput(audioPreview) }

        let audioDataOutput = AVCaptureAudioDataOutput()
        var monoAudioPreview: MonoAudioPreview?
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
            let preview = MonoAudioPreview()
            preview.attach(to: audioDataOutput)
            monoAudioPreview = preview
        }
        if device.supportsSessionPreset(.high) { session.sessionPreset = .high }
        session.commitConfiguration()

        guard isRequested(activation) else {
            teardown(session: session)
            return
        }

        currentDevice = device
        currentSession = session
        audioPreviewOutput = audioPreview
        self.audioDataOutput = monoAudioPreview == nil ? nil : audioDataOutput
        self.monoAudioPreview = monoAudioPreview
        session.startRunning()

        guard isRequested(activation) else {
            applyAudioOutput(isActive: false)
            return
        }

        applyAudioOutput(isActive: true)
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
        audioDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        monoAudioPreview?.stop()
        currentDevice = nil
        audioPreviewOutput = nil
        audioDataOutput = nil
        monoAudioPreview = nil
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

    private func hasRequestedActivation() -> Bool {
        stateLock.lock()
        let hasActivation = requestedActivation != nil
        stateLock.unlock()
        return hasActivation
    }

    private func applyAudioOutput(isActive: Bool) {
        let audibleVolume = isActive && !isAudioMuted ? outputVolume : 0
        let canRenderMono = usesMonoAudioOutput && monoAudioPreview != nil
        audioPreviewOutput?.volume = canRenderMono ? 0 : audibleVolume
        monoAudioPreview?.configure(isActive: canRenderMono && audibleVolume > 0, volume: audibleVolume)
    }

}

private final class MonoAudioPreview: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {

    private let queue = DispatchQueue(label: "com.prezenter.capture.mono-audio")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inputFormat: AVAudioFormat?
    private var monoFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var isActive = false
    private var volume: Float = 1

    override init() {
        super.init()
        engine.attach(player)
    }

    func attach(to output: AVCaptureAudioDataOutput) {
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func configure(isActive: Bool, volume: Float) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isActive = isActive
            self.volume = volume
            self.player.volume = volume
            if !isActive { self.stopPlayback() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.isActive = false
            self?.stopPlayback()
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isActive,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: streamDescription),
              let inputBuffer = makePCMBuffer(from: sampleBuffer, format: format) else { return }

        if inputFormat?.isEqual(format) != true || converter == nil {
            guard configureEngine(inputFormat: format) else { return }
        } else if !startPlaybackIfNeeded() {
            return
        }

        guard let monoFormat = monoFormat,
              let converter = converter,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat,
                                                  frameCapacity: inputBuffer.frameCapacity) else { return }
        do {
            try converter.convert(to: outputBuffer, from: inputBuffer)
            player.scheduleBuffer(outputBuffer)
        } catch {
            return
        }
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        let sourceBufferList = AudioBufferList.allocate(maximumBuffers: max(Int(format.channelCount), 1))
        defer { sourceBufferList.unsafeMutablePointer.deallocate() }
        var retainedBlockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: sourceBufferList.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: max(Int(format.channelCount), 1)),
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer)
        guard status == noErr else { return nil }

        pcmBuffer.frameLength = frameCount
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        guard sourceBufferList.count == destinationBuffers.count else { return nil }
        for index in 0..<sourceBufferList.count {
            let source = sourceBufferList[index]
            guard let sourceData = source.mData,
                  let destinationData = destinationBuffers[index].mData else { return nil }
            let byteCount = min(Int(source.mDataByteSize), Int(destinationBuffers[index].mDataByteSize))
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = UInt32(byteCount)
        }
        return pcmBuffer
    }

    private func configureEngine(inputFormat: AVAudioFormat) -> Bool {
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: inputFormat.sampleRate,
                                             channels: 1,
                                             interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: monoFormat) else { return false }

        stopPlayback()
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: monoFormat)
        self.inputFormat = inputFormat
        self.monoFormat = monoFormat
        self.converter = converter
        return startPlaybackIfNeeded()
    }

    private func startPlaybackIfNeeded() -> Bool {
        guard isActive else { return false }
        player.volume = volume
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            if !player.isPlaying { player.play() }
            return true
        } catch {
            return false
        }
    }

    private func stopPlayback() {
        player.stop()
        engine.stop()
        engine.reset()
    }

}
