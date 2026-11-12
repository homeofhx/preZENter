import Cocoa
import CoreGraphics
import ScreenCaptureKit

@available(macOS 12.3, *)
final class ScreenCaptureKitWindowCapturer: NSObject,
    DesktopCapturer, SCStreamOutput, SCStreamDelegate, DesktopCapturerDelegate {

    weak var delegate: DesktopCapturerDelegate?

    private let windowID: CGWindowID
    private let fallbackFrameRate: Int
    private let showsCursor: Bool
    private let imageContext = CIContext()
    private var stream: SCStream?
    private var fallbackCapturer: CoreGraphicsWindowCapturer?
    private var isStopped = true
    private var fallbackStarted = false

    init(windowID: CGWindowID, fallbackFrameRate: Int, showsCursor: Bool) {
        self.windowID = windowID
        self.fallbackFrameRate = fallbackFrameRate
        self.showsCursor = showsCursor
    }

    func start() {
        isStopped = false
        fallbackStarted = false
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) {
            [weak self] content, error in
            DispatchQueue.main.async {
                guard let self = self, !self.isStopped else { return }
                guard error == nil,
                      let window = content?.windows.first(where: { $0.windowID == self.windowID }) else {
                    self.startFallback()
                    return
                }
                self.beginStream(window: window)
            }
        }
    }

    func stop() {
        isStopped = true
        fallbackCapturer?.delegate = nil
        fallbackCapturer?.stop()
        fallbackCapturer = nil
        stream?.stopCapture { _ in }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = NSImage(cgImage: cgImage, size: .zero)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isStopped, !self.fallbackStarted else { return }
            self.delegate?.capturer(self, didCapture: image)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isStopped, !self.fallbackStarted else { return }
            self.delegate?.capturerDidLoseSource(self)
        }
    }

    func capturer(_ capturer: DesktopCapturer, didCapture image: NSImage) {
        guard !isStopped, capturer === fallbackCapturer else { return }
        delegate?.capturer(self, didCapture: image)
    }

    func capturerDidLoseSource(_ capturer: DesktopCapturer) {
        guard !isStopped, capturer === fallbackCapturer else { return }
        delegate?.capturerDidLoseSource(self)
    }

    private func beginStream(window: SCWindow) {
        guard !isStopped else { return }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = (NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main)?
            .backingScaleFactor ?? 1.0
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width * scale), 2)
        configuration.height = max(Int(window.frame.height * scale), 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = showsCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            stream = newStream
            newStream.startCapture { [weak self] error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.startFallback() }
            }
        } catch {
            startFallback()
        }
    }

    private func startFallback() {
        guard !isStopped, !fallbackStarted else { return }
        fallbackStarted = true
        stream?.stopCapture { _ in }
        stream = nil

        let capturer = CoreGraphicsWindowCapturer(windowID: windowID, frameRate: fallbackFrameRate, showsCursor: showsCursor)
        fallbackCapturer = capturer
        capturer.delegate = self
        capturer.start()
    }

}

@available(macOS 12.3, *)
final class ScreenCaptureKitScreenCapturer: NSObject,
    DesktopCapturer, SCStreamOutput, SCStreamDelegate, DesktopCapturerDelegate {

    weak var delegate: DesktopCapturerDelegate?

    private let displayID: CGDirectDisplayID
    private let fallbackFrameRate: Int
    private let showsCursor: Bool
    private let imageContext = CIContext()
    private var stream: SCStream?
    private var fallbackCapturer: CoreGraphicsScreenCapturer?
    private var isStopped = true
    private var fallbackStarted = false

    init(displayID: CGDirectDisplayID, fallbackFrameRate: Int, showsCursor: Bool) {
        self.displayID = displayID
        self.fallbackFrameRate = fallbackFrameRate
        self.showsCursor = showsCursor
    }

    func start() {
        isStopped = false
        fallbackStarted = false
        SCShareableContent.getExcludingDesktopWindows(false,
                                                      onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self = self, !self.isStopped else { return }
                guard error == nil,
                      let display = content?.displays.first(where: { $0.displayID == self.displayID }) else {
                    self.startFallback()
                    return
                }
                self.beginStream(display: display)
            }
        }
    }

    func stop() {
        isStopped = true
        fallbackCapturer?.delegate = nil
        fallbackCapturer?.stop()
        fallbackCapturer = nil
        stream?.stopCapture { _ in }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = NSImage(cgImage: cgImage, size: .zero)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isStopped, !self.fallbackStarted else { return }
            self.delegate?.capturer(self, didCapture: image)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isStopped, !self.fallbackStarted else { return }
            self.delegate?.capturerDidLoseSource(self)
        }
    }

    func capturer(_ capturer: DesktopCapturer, didCapture image: NSImage) {
        guard !isStopped, capturer === fallbackCapturer else { return }
        delegate?.capturer(self, didCapture: image)
    }

    func capturerDidLoseSource(_ capturer: DesktopCapturer) {
        guard !isStopped, capturer === fallbackCapturer else { return }
        delegate?.capturerDidLoseSource(self)
    }

    private func beginStream(display: SCDisplay) {
        guard !isStopped else { return }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let scale = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        })?.backingScaleFactor ?? 1.0
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(CGFloat(display.width) * scale), 2)
        configuration.height = max(Int(CGFloat(display.height) * scale), 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = showsCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            stream = newStream
            newStream.startCapture { [weak self] error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.startFallback() }
            }
        } catch {
            startFallback()
        }
    }

    private func startFallback() {
        guard !isStopped, !fallbackStarted else { return }
        fallbackStarted = true
        stream?.stopCapture { _ in }
        stream = nil

        let capturer = CoreGraphicsScreenCapturer(displayID: displayID, frameRate: fallbackFrameRate, showsCursor: showsCursor)
        fallbackCapturer = capturer
        capturer.delegate = self
        capturer.start()
    }

}
