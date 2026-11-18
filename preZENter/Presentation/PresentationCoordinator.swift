import Cocoa

final class PresentationCoordinator {

    var onSourceLost: ((ContentSource) -> Void)?

    private weak var liveWindow: LiveWindow?
    private let desktopCapture = DesktopCaptureController()
    private let videoDevicePipeline = CaptureDevicePipeline(channel: .videoDevice, queueLabel: "com.prezenter.capture.video-device")
    private let iOSDevicePipeline = CaptureDevicePipeline(channel: .iOSDevice, queueLabel: "com.prezenter.capture.ios-device")

    private var activeSource: ContentSource?
    private var presentationID: UInt64 = 0
    private var settingsObservers: [NSObjectProtocol] = []

    init(liveWindow: LiveWindow) {
        self.liveWindow = liveWindow

        videoDevicePipeline.onDeviceLost = { [weak self] activation in
            self?.captureDeviceWasLost(activation, kind: .videoDevice)
        }
        iOSDevicePipeline.onDeviceLost = { [weak self] activation in
            self?.captureDeviceWasLost(activation, kind: .iOSDevice)
        }
        settingsObservers.append(NotificationCenter.default.addObserver(forName: .captureSettingsDidChange,
                                                                        object: ApplicationSettings.shared,
                                                                        queue: .main) { [weak self] _ in
            self?.restartDesktopCaptureIfNeeded()
        })
        settingsObservers.append(NotificationCenter.default.addObserver(forName: .audioSettingsDidChange,
                                                                        object: ApplicationSettings.shared,
                                                                        queue: .main) { [weak self] _ in
            self?.applyAudioSettings()
        })
        applyAudioSettings()
    }

    deinit {
        settingsObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func present(_ source: ContentSource) {
        present(source, activatesWindow: true)
    }

    private func present(_ source: ContentSource, activatesWindow: Bool) {
        guard let liveWindow = liveWindow else { return }
        presentationID &+= 1
        let currentID = presentationID
        activeSource = source

        desktopCapture.stop()
        videoDevicePipeline.deactivate(liveWindow: liveWindow)
        iOSDevicePipeline.deactivate(liveWindow: liveWindow)
        liveWindow.beginPresentation(presentationID: currentID)

        switch source {
        case .applicationWindow, .screen:
            desktopCapture.start(source: source, activatesWindow: activatesWindow, onFrame: { [weak self] image in
                guard let self = self,
                      self.presentationID == currentID,
                      self.activeSource == source else { return }
                self.liveWindow?.showImage(image, presentationID: currentID)
            }, onSourceLost: { [weak self] in
                self?.desktopSourceWasLost(source, presentationID: currentID)
            })
        case .videoDevice(let uniqueID):
            videoDevicePipeline.activate(uniqueID: uniqueID, presentationID: currentID, liveWindow: liveWindow)
        case .iOSDevice(let uniqueID):
            iOSDevicePipeline.activate(uniqueID: uniqueID, presentationID: currentID, liveWindow: liveWindow)
        }
    }

    func stopAndShowIdle() {
        guard let liveWindow = liveWindow else { return }
        presentationID &+= 1
        activeSource = nil
        desktopCapture.stop()
        videoDevicePipeline.deactivate(liveWindow: liveWindow)
        iOSDevicePipeline.deactivate(liveWindow: liveWindow)
        liveWindow.beginPresentation(presentationID: presentationID)
        liveWindow.showIdleScreen(presentationID: presentationID)
    }

    func shutdown() {
        guard let liveWindow = liveWindow else { return }
        presentationID &+= 1
        activeSource = nil
        desktopCapture.stop()
        videoDevicePipeline.shutdown(liveWindow: liveWindow)
        iOSDevicePipeline.shutdown(liveWindow: liveWindow)
    }

    private func desktopSourceWasLost(_ source: ContentSource, presentationID: UInt64) {
        guard self.presentationID == presentationID, activeSource == source else { return }
        onSourceLost?(source)
    }

    private func captureDeviceWasLost(_ activation: CaptureDevicePipeline.Activation, kind: ContentSourceKind) {
        let source: ContentSource
        switch kind {
        case .videoDevice: source = .videoDevice(activation.uniqueID)
        case .iOSDevice: source = .iOSDevice(activation.uniqueID)
        case .applicationWindow, .screen: return
        }

        guard presentationID == activation.presentationID,
              activeSource == source else { return }
        onSourceLost?(source)
    }

    private func restartDesktopCaptureIfNeeded() {
        guard let source = activeSource else { return }
        switch source {
        case .applicationWindow, .screen:
            present(source, activatesWindow: false)
        case .videoDevice, .iOSDevice:
            break
        }
    }

    private func applyAudioSettings() {
        let settings = ApplicationSettings.shared
        let volume = Float(settings.outputVolume) / 100
        videoDevicePipeline.updateAudioConfiguration(volume: volume,
                                                     isMuted: settings.mutesVideoDeviceAudio,
                                                     usesMonoOutput: settings.usesMonoAudioOutput)
        iOSDevicePipeline.updateAudioConfiguration(volume: volume,
                                                   isMuted: settings.mutesIOSDeviceAudio,
                                                   usesMonoOutput: settings.usesMonoAudioOutput)
    }

}
