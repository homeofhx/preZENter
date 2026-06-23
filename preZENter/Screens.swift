import Cocoa
import CoreGraphics
import ScreenCaptureKit

class Screens: NSObject {
    
    public var onSourceLost: (() -> Void)?   // Called on the main thread when the captured screen disappears
    
    private var activeCapturer: ScreenCapturer?
    
    public func getAllScreens() -> [(title: String, displayID: CGDirectDisplayID)] {
        return NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID else { return nil }
            
            if #available(macOS 10.15, *) { return (screen.localizedName, displayID) }
            let size = screen.frame.size
            return ("Screen: \(Int(size.width))x\(Int(size.height))", displayID)
        }
    }
    
    public func selectScreen(displayID: CGDirectDisplayID, liveWindow: LiveWindow) {
        stopScreenSession(liveWindow: liveWindow)
        
        if #available(macOS 12.3, *) {
            let capturer = SCKScreenCapturer(displayID: displayID, liveWindow: liveWindow, delegate: self)
            activeCapturer = capturer
            capturer.start()
        } else {
            let capturer = CGScreenCapturer(displayID: displayID, liveWindow: liveWindow, delegate: self)
            activeCapturer = capturer
            capturer.start()
        }
    }
    
    public func stopScreenSession(liveWindow: LiveWindow) {
        activeCapturer?.stop()
        activeCapturer = nil
        liveWindow.stopLiveView()
    }
    
}

// MARK: - Internal protocols

private protocol ScreenCapturer: AnyObject {
    func start()
    func stop()
}

private protocol ScreenCapturerDelegate: AnyObject {
    func capturerDidLoseSource()
}

// MARK: - Core Graphics capturer
private class CGScreenCapturer: ScreenCapturer {
    
    private var captureTimer: Timer?
    private var consecutiveFailures = 0
    private weak var liveWindow: LiveWindow?
    private weak var delegate: ScreenCapturerDelegate?
    
    private let displayID: CGDirectDisplayID
    private static let maxFailures = 5   // ~0.14 s at 35 fps before declaring lost
    
    init(displayID: CGDirectDisplayID, liveWindow: LiveWindow, delegate: ScreenCapturerDelegate) {
        self.displayID = displayID
        self.liveWindow = liveWindow
        self.delegate = delegate
    }
    
    public func start() {
        captureTimer?.invalidate()
        let dID = displayID
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            guard let ref = CGDisplayCreateImage(dID) else {
                self.consecutiveFailures += 1
                if self.consecutiveFailures >= CGScreenCapturer.maxFailures {
                    self.captureTimer?.invalidate()
                    self.captureTimer = nil
                    self.delegate?.capturerDidLoseSource()
                }
                
                return
            }
            
            self.consecutiveFailures = 0
            let image = NSImage(cgImage: ref, size: NSZeroSize)
            let resultImage = image.drawingCursor(for: CGDisplayBounds(dID))
            DispatchQueue.main.async { self.liveWindow?.updateWindowLayerImage(resultImage) }
        }
        
        RunLoop.current.add(captureTimer!, forMode: .common)
    }
    
    public func stop() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
}

// MARK: - Cursor overlay extension
extension NSImage {
    func drawingCursor(for sourceBounds: CGRect) -> NSImage {
        guard let event = CGEvent(source: nil) else { return self }
        let mouseLocation = event.location
        
        if sourceBounds.contains(mouseLocation) {
            let cursor = NSCursor.arrow
            let cursorImage = cursor.image
            let hotSpot = cursor.hotSpot
            
            let result = NSImage(size: self.size)
            result.lockFocus()
            self.draw(in: NSRect(origin: .zero, size: self.size))
            
            let scaleX = self.size.width / sourceBounds.width
            let scaleY = self.size.height / sourceBounds.height
            
            let finalX = (mouseLocation.x - sourceBounds.minX - hotSpot.x) * scaleX
            let finalY = self.size.height - (mouseLocation.y - sourceBounds.minY - hotSpot.y) * scaleY - cursorImage.size.height
            
            cursorImage.draw(at: NSPoint(x: finalX, y: finalY), from: .zero, operation: .sourceOver, fraction: 1.0)
            result.unlockFocus()
            
            return result
        }
        
        return self
    }
}

// MARK: - ScreenCaptureKit capturer
@available(macOS 12.3, *)
private class SCKScreenCapturer: NSObject, ScreenCapturer, SCStreamOutput, SCStreamDelegate {
    
    private var stream: SCStream?
    private var fallbackCapturer: CGScreenCapturer?
    private weak var liveWindow: LiveWindow?
    private weak var delegate: ScreenCapturerDelegate?
    
    private let displayID: CGDirectDisplayID
    private let ciContext = CIContext()
    
    init(displayID: CGDirectDisplayID, liveWindow: LiveWindow, delegate: ScreenCapturerDelegate) {
        self.displayID = displayID
        self.liveWindow = liveWindow
        self.delegate = delegate
    }
    
    public func start() {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self else { return }
            if error != nil { self.fallbackToCG(); return }
            
            guard let scDisplay = content?.displays.first(where: { $0.displayID == self.displayID }) else {
                DispatchQueue.main.async { self.delegate?.capturerDidLoseSource() }
                return
            }
            
            self.beginStream(scDisplay: scDisplay)
        }
    }
    
    public func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        fallbackCapturer?.stop()
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
     
     public func stream(_ stream: SCStream, didStopWithError error: Error) {
         delegate?.capturerDidLoseSource()
     }
    
    private func beginStream(scDisplay: SCDisplay) {
        let filter = SCContentFilter(
            display: scDisplay,
            excludingApplications: [],
            exceptingWindows: [])
        
        let scale = NSScreen.screens
            .first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                      as? CGDirectDisplayID) == displayID }?
            .backingScaleFactor ?? 1.0
        
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(scDisplay.width) * scale)
        config.height = Int(CGFloat(scDisplay.height) * scale)
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
             let cgCapturer = CGScreenCapturer(displayID: self.displayID, liveWindow: lw, delegate: del)
             self.fallbackCapturer = cgCapturer
             cgCapturer.start()
         }
     }
    
}

// MARK: - Delegate conformance
extension Screens: ScreenCapturerDelegate {
    fileprivate func capturerDidLoseSource() {
        DispatchQueue.main.async { self.onSourceLost?() }
    }
}
