import Cocoa
import AVFoundation

class LiveWindow: NSWindowController {
    
    private var windowLayer: NSImageView!
    private var videoDevPreview: VideoDevPreview!
    private var idleLayer: NSImageView!
    private var idleScreenTimer: Timer?
    private var fadeOverlay: NSView!
    private var idleScreenActiveStatus = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    
    convenience init() {
        let liveWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 576),
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
        
        videoDevPreview = VideoDevPreview(frame: contentView.bounds)
        videoDevPreview.autoresizingMask = [.width, .height]
        videoDevPreview.isHidden = true
        contentView.addSubview(videoDevPreview)
        
        idleLayer = NSImageView(frame: contentView.bounds)
        idleLayer.autoresizingMask = [.width, .height]
        idleLayer.imageScaling = .scaleProportionallyUpOrDown
        idleLayer.wantsLayer = true
        contentView.addSubview(idleLayer)
        
        fadeOverlay = NSView(frame: contentView.bounds)
        fadeOverlay.autoresizingMask = [.width, .height]
        fadeOverlay.wantsLayer = true
        fadeOverlay.layer?.backgroundColor = NSColor.black.cgColor
        fadeOverlay.alphaValue = 0
        contentView.addSubview(fadeOverlay)
        
        refreshIdleScreenContents()
        idleLayer.isHidden = false
        
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                               object: self.window,
                                               queue: .main
        ) { [weak self] _ in self?.refreshIdleScreenContents() })
        
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: .idleScreenSettingsDidChange,
                                               object: nil,
                                               queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.refreshIdleScreenContents()
            if !self.idleLayer.isHidden { self.changeIdleScreenTimerVisibility() }
        })
    }
    
    // Memory leak prevention
    deinit {
        NotificationCenter.default.removeObserver(self)
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
        idleScreenTimer?.invalidate()
    }
    
    public func updateWindowLayerImage(_ image: NSImage) {
        guard !idleScreenActiveStatus else { return }
        windowLayer.image = image
    }
    
    public func setupLiveView(session: AVCaptureSession) {
        stopLiveView()
        hideIdleScreen()
        
        videoDevPreview.previewLayer.session = session
        videoDevPreview.previewLayer.videoGravity = .resizeAspect
        videoDevPreview.isHidden = false
        
        self.window?.makeKeyAndOrderFront(nil)
    }
    
    public func stopLiveView() {
        videoDevPreview.previewLayer.session = nil
        videoDevPreview.isHidden = true
        windowLayer.image = nil
    }
    
    public func showIdleScreen() {
        idleScreenActiveStatus = true
        refreshIdleScreenContents()
        idleLayer.isHidden = false
        changeIdleScreenTimerVisibility()
        window?.makeKeyAndOrderFront(nil)
    }
    
    public func hideIdleScreen() {
        idleScreenActiveStatus = false
        idleLayer.isHidden = true
        hideIdleScreenTimer()
    }
    
    public func refreshIdleScreenContents() {
        guard let size = window?.contentView?.bounds.size,size.width > 0, size.height > 0 else { return }
        idleLayer.image = IdleScreen.renderIdleScreenContents(for: size)
    }
    
    public func performTransition(then switchContent: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fadeOverlay.animator().alphaValue = 1.0
        }) {
            switchContent()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.fadeOverlay.animator().alphaValue = 0.0
            })
        }
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

// MARK: - Video dev subview
private class VideoDevPreview: NSView {
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("VideoPreviewView's layer must be an AVCaptureVideoPreviewLayer")
        }
        
        return layer
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override func makeBackingLayer() -> CALayer {
        return AVCaptureVideoPreviewLayer()
    }
    
}
