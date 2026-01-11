import Cocoa
import AVFoundation

class LiveWindow: NSWindowController {
    
    private var windowLayer: NSImageView!
    private var videoDevLayer: AVCaptureVideoPreviewLayer?
    
    convenience init() {
        let LiveWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 576),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        LiveWindow.title = "preZENter - Live Window"
        LiveWindow.center()
        LiveWindow.backgroundColor = NSColor.black
        self.init(window: LiveWindow)
        self.window?.makeKeyAndOrderFront(nil)
        
        windowLayer = NSImageView(frame: LiveWindow.contentView!.bounds)
        windowLayer.autoresizingMask = [.width, .height]
        windowLayer.imageScaling = .scaleProportionallyUpOrDown
        windowLayer.wantsLayer = true
        LiveWindow.contentView?.addSubview(windowLayer)
    }
    
    public func updateWindowLayerImage(_ image: NSImage) {
        windowLayer.image = image
    }
    
    public func setupLiveView(session: AVCaptureSession) {
        stopLiveView()
        
        let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        newPreviewLayer.videoGravity = .resizeAspect
        
        if let contentView = self.window?.contentView {
            newPreviewLayer.frame = contentView.bounds
            contentView.layer = newPreviewLayer
            contentView.wantsLayer = true
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self.window, queue: .main) { [weak self] _ in
                self?.videoDevLayer?.frame = contentView.bounds
            }
        }
        
        videoDevLayer = newPreviewLayer
        self.window?.makeKeyAndOrderFront(nil)
    }
    
    public func stopLiveView() {
        videoDevLayer = nil
        windowLayer.image = nil
    }
    
}
