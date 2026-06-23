import Cocoa
import CoreGraphics
import ScreenCaptureKit

class Windows: NSObject {
    
    public var onWindowLost: (() -> Void)?
    
    private var activeCapturer: WindowCapturer?
    private let minWindowBound: CGFloat = 125
    
    public func getVisibleWindows() -> [(title: String, windowID: CGWindowID)] {
        let windowInfo = CGWindowListCopyWindowInfo(CGWindowListOption(arrayLiteral:
                .excludeDesktopElements, .optionOnScreenOnly), kCGNullWindowID)
        guard let windowList = windowInfo as? [[String: AnyObject]] else { return [] }
        
        return windowList.compactMap { window in
            guard
                let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                bounds.width >= minWindowBound, bounds.height >= minWindowBound,
                let content = window[kCGWindowName as String] as? String, !content.isEmpty,
                let appName = window[kCGWindowOwnerName as String] as? String, appName != "preZENter",
                let windowNum = window[kCGWindowNumber as String] as? NSNumber
            else { return nil }
            
            return ("\(appName): \(content)", windowNum.uint32Value)
        }
    }
    
    public func selectWindow(id: CGWindowID, liveWindow: LiveWindow) {
        stopWindowSession(liveWindow: liveWindow)
        
        if #available(macOS 12.3, *) {
            let capturer = SCKWindowCapturer(windowID: id, liveWindow: liveWindow, delegate: self)
            activeCapturer = capturer
            capturer.start()
        } else {
            let capturer = CGWindowCapturer(windowID: id, liveWindow: liveWindow, delegate: self)
            activeCapturer = capturer
            capturer.start()
        }
    }
    
    public func stopWindowSession(liveWindow: LiveWindow) {
        activeCapturer?.stop()
        activeCapturer = nil
        liveWindow.stopLiveView()
    }
    
}

// MARK: - Protocols

private protocol WindowCapturer: AnyObject {
    func start()
    func stop()
}

private protocol WindowCapturerDelegate: AnyObject {
    func capturerDidLoseSource()
}

// MARK: - CoreGraphics capturer
private class CGWindowCapturer: WindowCapturer {
    
    private var captureTimer: Timer?
    private weak var liveWindow: LiveWindow?
    private weak var delegate: WindowCapturerDelegate?
    
    private let windowID: CGWindowID
    
    init(windowID: CGWindowID, liveWindow: LiveWindow, delegate: WindowCapturerDelegate) {
        self.windowID = windowID
        self.liveWindow = liveWindow
        self.delegate = delegate
    }
    
    public func start() {
        captureTimer?.invalidate()
        let winID = windowID
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            guard let ref = CGWindowListCreateImage(.null, .optionIncludingWindow, winID,
                                                    [.bestResolution, .boundsIgnoreFraming]) else {
                self.captureTimer?.invalidate()
                self.captureTimer = nil
                self.delegate?.capturerDidLoseSource()
                return
            }
            
            let image = NSImage(cgImage: ref, size: NSZeroSize)
            var resultImage = image
            
            if let windowInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, winID) as? [[String: AnyObject]],
               let window = windowInfo.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == winID }),
               let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
               let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                resultImage = image.drawingCursor(for: bounds) }
            
            DispatchQueue.main.async { self.liveWindow?.updateWindowLayerImage(resultImage) }
        }
        
        RunLoop.current.add(captureTimer!, forMode: .common)
    }
    
    public func stop() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
}

// MARK: - ScreenCaptureKit capturer
@available(macOS 12.3, *)
private class SCKWindowCapturer: NSObject, WindowCapturer, SCStreamOutput, SCStreamDelegate {
    
    private var stream: SCStream?
    private var isStopping = false
    private var fallbackCapturer: CGWindowCapturer?
    private weak var liveWindow: LiveWindow?
    private weak var delegate: WindowCapturerDelegate?
    
    private let windowID: CGWindowID
    private let ciContext = CIContext()
    
    init(windowID: CGWindowID, liveWindow: LiveWindow, delegate: WindowCapturerDelegate) {
        self.windowID = windowID
        self.liveWindow = liveWindow
        self.delegate = delegate
    }
    
    public func start() {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self = self else { return }
            if error != nil { self.fallbackToCG(); return }
            
            guard let scWindow = content?.windows.first(where: { $0.windowID == self.windowID }) else {
                DispatchQueue.main.async { self.delegate?.capturerDidLoseSource() }
                return
            }
            
            self.beginStream(scWindow: scWindow)
        }
    }
    
    public func stop() {
        isStopping = true
        stream?.stopCapture { _ in }
        stream = nil
        fallbackCapturer?.stop()
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !isStopping else { return }
        self.stream = nil
        delegate?.capturerDidLoseSource()
    }
    
    public func stream(_ stream: SCStream,
                       didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSZeroSize)
        DispatchQueue.main.async { [weak self] in self?.liveWindow?.updateWindowLayerImage(nsImage) }
    }
    
    private func beginStream(scWindow: SCWindow) {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = (NSScreen.screens.first { $0.frame.intersects(scWindow.frame) } ?? NSScreen.main)?.backingScaleFactor ?? 1.0
        
        let config = SCStreamConfiguration()
        config.width = max(Int(scWindow.frame.width * scale), 2)
        config.height = max(Int(scWindow.frame.height * scale), 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            newStream.startCapture { [weak self] error in if error != nil { self?.fallbackToCG() } }
            stream = newStream
        } catch {
            fallbackToCG()
        }
    }
    
     private func fallbackToCG() {
         DispatchQueue.main.async { [weak self] in
             guard let self = self, let lw = self.liveWindow, let del = self.delegate else { return }
             let cgCapturer = CGWindowCapturer(windowID: self.windowID, liveWindow: lw, delegate: del)
             self.fallbackCapturer = cgCapturer
             cgCapturer.start()
         }
     }
    
}

// MARK: - Delegate conformance
extension Windows: WindowCapturerDelegate {
    fileprivate func capturerDidLoseSource() {
        DispatchQueue.main.async { self.onWindowLost?() }
    }
}
