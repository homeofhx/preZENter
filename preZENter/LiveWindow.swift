import Cocoa
import AVFoundation

class LiveWindow: NSWindowController {
    
    private var windowLayer: NSImageView!
    private var videoDevLayer: AVCaptureVideoPreviewLayer?
    private var idleLayer: NSImageView!
    private var idleScreenTimer: Timer?
    
    convenience init() {
        let liveWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 576),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        liveWindow.title = "preZENter - Live Window"
        liveWindow.center()
        liveWindow.backgroundColor = NSColor.black
        self.init(window: liveWindow)
        self.window?.makeKeyAndOrderFront(nil)
        
        guard let contentView = liveWindow.contentView else { return }
        
        windowLayer = NSImageView(frame: contentView.bounds)
        windowLayer.autoresizingMask = [.width, .height]
        windowLayer.imageScaling = .scaleProportionallyUpOrDown
        windowLayer.wantsLayer = true
        contentView.addSubview(windowLayer)
        
        idleLayer = NSImageView(frame: contentView.bounds)
        idleLayer.autoresizingMask = [.width, .height]
        idleLayer.imageScaling = .scaleProportionallyUpOrDown
        idleLayer.wantsLayer = true
        contentView.addSubview(idleLayer)
        
        refreshIdleScreenContents()
        idleLayer.isHidden = false
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self.window,
            queue: .main
        ) { [weak self] _ in self?.refreshIdleScreenContents() }
        
        NotificationCenter.default.addObserver(
            forName: .idleScreenSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.refreshIdleScreenContents()
            if !self.idleLayer.isHidden { self.changeIdleScreenTimerVisibility() }
        }
    }
    
    public func updateWindowLayerImage(_ image: NSImage) {
        if !idleLayer.isHidden { hideIdleScreen() }
        windowLayer.image = image
    }
    
    public func setupLiveView(session: AVCaptureSession) {
        stopLiveView()
        hideIdleScreen()
        
        let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        newPreviewLayer.videoGravity = .resizeAspect
        
        if let contentView = self.window?.contentView {
            newPreviewLayer.frame = contentView.bounds
            contentView.layer = newPreviewLayer
            contentView.wantsLayer = true
            NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self.window,
            queue: .main) {
                [weak self] _ in self?.videoDevLayer?.frame = contentView.bounds
            }
        }
        
        videoDevLayer = newPreviewLayer
        self.window?.makeKeyAndOrderFront(nil)
    }
    
    public func stopLiveView() {
        videoDevLayer = nil
        windowLayer.image = nil
    }
    
    public func showIdleScreen() {
        refreshIdleScreenContents()
        idleLayer.isHidden = false
        changeIdleScreenTimerVisibility()
        window?.makeKeyAndOrderFront(nil)
    }
    
    public func hideIdleScreen() {
        idleLayer.isHidden = true
        hideIdleScreenTimer()
    }
    
    public func refreshIdleScreenContents() {
        guard let size = window?.contentView?.bounds.size,size.width > 0, size.height > 0 else { return }
        idleLayer.image = IdleScreen.renderIdleScreenContents(for: size)
    }
    
    private func changeIdleScreenTimerVisibility() {
        if IdleScreenSettings.shared.showTime {
            showIdleScreenTimer()
        } else {
            hideIdleScreenTimer()
        }
    }
    
    private func showIdleScreenTimer() {
        guard idleScreenTimer == nil else { return }
        idleScreenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshIdleScreenContents()
        }
        RunLoop.current.add(idleScreenTimer!, forMode: .common)
    }
    
    private func hideIdleScreenTimer() {
        idleScreenTimer?.invalidate()
        idleScreenTimer = nil
    }
}
