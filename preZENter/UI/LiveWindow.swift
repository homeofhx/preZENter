import Cocoa
import AVFoundation

final class LiveWindow: NSWindowController {

    var onPresentationStatusChanged: ((Bool) -> Void)?

    private(set) var isPresenting = false {
        didSet {
            if isPresenting != oldValue { onPresentationStatusChanged?(isPresenting) }
        }
    }

    private var imageView: NSImageView!
    private var videoDevicePreview: CapturePreviewView!
    private var iOSDevicePreview: CapturePreviewView!
    private var idleView: NSImageView!
    private var sourceNameLabel: NSTextField!
    private var fadeOverlay: NSView!
    private var presentedSourceName = ""
    private var activePresentationID: UInt64 = 0
    private var transitionID: UInt64 = 0
    private var idleScreenTimer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var titleBarTrackingArea: NSTrackingArea?
    private weak var titleBarTrackingView: NSView?

    convenience init() {
        let liveWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 576),
                                  styleMask: [.titled, .resizable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered,
                                  defer: false)
        liveWindow.title = "preZENter - Live Window"
        liveWindow.center()
        liveWindow.backgroundColor = .black
        self.init(window: liveWindow)
        setTitleBarVisible(false)

        guard let contentView = liveWindow.contentView else { return }
        configureTitleBarTracking(contentView: contentView)

        imageView = NSImageView(frame: contentView.bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        contentView.addSubview(imageView)

        videoDevicePreview = CapturePreviewView(frame: contentView.bounds)
        videoDevicePreview.autoresizingMask = [.width, .height]
        videoDevicePreview.isHidden = true
        contentView.addSubview(videoDevicePreview)

        iOSDevicePreview = CapturePreviewView(frame: contentView.bounds)
        iOSDevicePreview.autoresizingMask = [.width, .height]
        iOSDevicePreview.isHidden = true
        contentView.addSubview(iOSDevicePreview)

        idleView = NSImageView(frame: contentView.bounds)
        idleView.autoresizingMask = [.width, .height]
        idleView.imageScaling = .scaleProportionallyUpOrDown
        idleView.wantsLayer = true
        contentView.addSubview(idleView)

        sourceNameLabel = NSTextField(labelWithString: "")
        sourceNameLabel.textColor = .white
        sourceNameLabel.maximumNumberOfLines = 1
        sourceNameLabel.cell?.lineBreakMode = .byTruncatingTail
        sourceNameLabel.cell?.usesSingleLineMode = true
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        textShadow.shadowBlurRadius = 3
        textShadow.shadowOffset = NSSize(width: 0, height: -1)
        sourceNameLabel.shadow = textShadow
        sourceNameLabel.isHidden = true
        contentView.addSubview(sourceNameLabel)

        fadeOverlay = NSView(frame: contentView.bounds)
        fadeOverlay.autoresizingMask = [.width, .height]
        fadeOverlay.wantsLayer = true
        fadeOverlay.layer?.backgroundColor = NSColor.black.cgColor
        fadeOverlay.alphaValue = 0
        contentView.addSubview(fadeOverlay)

        refreshIdleScreenContents()
        updateLiveWindowText()
        idleView.isHidden = false
        liveWindow.makeKeyAndOrderFront(nil)
        updateTitleBarVisibilityForCurrentMouseLocation()
        registerLifecycleObservers()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        idleScreenTimer?.invalidate()
        if let trackingArea = titleBarTrackingArea { titleBarTrackingView?.removeTrackingArea(trackingArea) }
    }

    override func mouseEntered(with event: NSEvent) {
        setTitleBarVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setTitleBarVisible(false)
    }

    func beginPresentation(presentationID: UInt64) {
        activePresentationID = presentationID
        hideIdleScreenTimer()
        idleView.isHidden = true
        imageView.image = nil
        videoDevicePreview.isHidden = true
        iOSDevicePreview.isHidden = true
        updatePresentationStatus()
    }

    func setPresentedSourceName(_ name: String?) {
        presentedSourceName = name ?? ""
        updateLiveWindowText()
    }

    func showImage(_ image: NSImage, presentationID: UInt64) {
        guard presentationID == activePresentationID else { return }
        imageView.image = image
        videoDevicePreview.isHidden = true
        iOSDevicePreview.isHidden = true
        updatePresentationStatus()
    }

    func showCapturePreview(session: AVCaptureSession, channel: CapturePreviewChannel, presentationID: UInt64) {
        guard presentationID == activePresentationID else { return }
        let preview = capturePreview(for: channel)
        let otherPreview = capturePreview(for: channel == .videoDevice ? .iOSDevice : .videoDevice)

        imageView.image = nil
        otherPreview.isHidden = true
        if preview.previewLayer.session !== session {
            preview.previewLayer.session = session
            preview.previewLayer.videoGravity = .resizeAspect
        }
        preview.isHidden = false
        updatePresentationStatus()
    }

    func hideCapturePreview(session: AVCaptureSession, channel: CapturePreviewChannel, presentationID: UInt64) {
        guard presentationID == activePresentationID else { return }
        let preview = capturePreview(for: channel)
        guard preview.previewLayer.session === session else { return }
        preview.isHidden = true
        updatePresentationStatus()
    }

    func detachCapturePreview(session: AVCaptureSession, channel: CapturePreviewChannel) {
        let preview = capturePreview(for: channel)
        guard preview.previewLayer.session === session else { return }
        preview.previewLayer.session = nil
        preview.isHidden = true
        updatePresentationStatus()
    }

    func showIdleScreen(presentationID: UInt64) {
        guard presentationID == activePresentationID else { return }
        imageView.image = nil
        videoDevicePreview.isHidden = true
        iOSDevicePreview.isHidden = true
        refreshIdleScreenContents()
        idleView.isHidden = false
        updateIdleScreenTimerVisibility()
        updatePresentationStatus()
    }

    func performTransition(then switchContent: @escaping () -> Void) {
        transitionID &+= 1
        let currentTransitionID = transitionID
        fadeOverlay.layer?.removeAllAnimations()

        let settings = ApplicationSettings.shared
        let duration = settings.transitionDuration
        guard settings.fadesBetweenContents, duration > 0 else {
            fadeOverlay.alphaValue = 0
            switchContent()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fadeOverlay.animator().alphaValue = 1.0
        }) { [weak self] in
            guard let self = self,
                  self.transitionID == currentTransitionID else { return }
            switchContent()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.fadeOverlay.animator().alphaValue = 0.0
            })
        }
    }

    func refreshIdleScreenContents() {
        guard let size = window?.contentView?.bounds.size,
              size.width > 0,
              size.height > 0 else { return }
        idleView.image = IdleScreen.renderIdleScreenContents(for: size)
    }

    private func capturePreview(for channel: CapturePreviewChannel) -> CapturePreviewView {
        switch channel {
        case .videoDevice: return videoDevicePreview
        case .iOSDevice: return iOSDevicePreview
        }
    }

    private func updatePresentationStatus() {
        let hasImage = imageView.image != nil
        let hasVideoDevice = !videoDevicePreview.isHidden && videoDevicePreview.previewLayer.session != nil
        let hasIOSDevice = !iOSDevicePreview.isHidden && iOSDevicePreview.previewLayer.session != nil
        isPresenting = idleView.isHidden && (hasImage || hasVideoDevice || hasIOSDevice)
    }

    private func configureTitleBarTracking(contentView: NSView) {
        let trackingArea = NSTrackingArea(rect: .zero,
                                          options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                          owner: self,
                                          userInfo: nil)
        let trackingView = contentView.superview ?? contentView
        trackingView.addTrackingArea(trackingArea)
        titleBarTrackingArea = trackingArea
        titleBarTrackingView = trackingView
    }

    private func registerLifecycleObservers() {
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main) { [weak self] _ in
                self?.refreshIdleScreenContents()
                self?.layoutLiveWindowText()
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: .idleScreenSettingsDidChange,
            object: nil,
            queue: .main) { [weak self] _ in
                guard let self = self else { return }
                self.refreshIdleScreenContents()
                if !self.idleView.isHidden { self.updateIdleScreenTimerVisibility() }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: .liveWindowTextSettingsDidChange,
            object: nil,
            queue: .main) { [weak self] _ in
            self?.updateLiveWindowText()
        })
    }

    private func updateLiveWindowText() {
        guard sourceNameLabel != nil else { return }
        let settings = LiveWindowTextSettings.shared
        let text: String
        if settings.showsPresentedSourceName {
            text = presentedSourceName
        } else if settings.showsCustomText {
            text = settings.customText
        } else {
            text = ""
        }

        sourceNameLabel.stringValue = text
        sourceNameLabel.font = .systemFont(ofSize: settings.fontSize, weight: .semibold)
        sourceNameLabel.isHidden = text.isEmpty
        layoutLiveWindowText()
    }

    private func layoutLiveWindowText() {
        guard let contentView = window?.contentView,
              sourceNameLabel != nil,
              !sourceNameLabel.isHidden else { return }

        let settings = LiveWindowTextSettings.shared
        let gap: CGFloat = 16
        let maximumWidth = max(contentView.bounds.width - gap * 2, 1)
        let fittingSize = sourceNameLabel.fittingSize
        let labelSize = NSSize(width: min(ceil(fittingSize.width), maximumWidth), height: ceil(fittingSize.height))
        let origin: NSPoint
        switch settings.position {
        case .topLeft:
            origin = NSPoint(x: gap, y: contentView.bounds.height - gap - labelSize.height)
        case .topRight:
            origin = NSPoint(x: contentView.bounds.width - gap - labelSize.width,
                             y: contentView.bounds.height - gap - labelSize.height)
        case .bottomLeft:
            origin = NSPoint(x: gap, y: gap)
        case .bottomRight:
            origin = NSPoint(x: contentView.bounds.width - gap - labelSize.width, y: gap)
        }
        sourceNameLabel.frame = NSRect(origin: origin, size: labelSize)
    }

    private func updateTitleBarVisibilityForCurrentMouseLocation() {
        guard let liveWindow = window else { return }
        setTitleBarVisible(liveWindow.frame.contains(NSEvent.mouseLocation))
    }

    private func setTitleBarVisible(_ isVisible: Bool) {
        guard let liveWindow = window else { return }
        liveWindow.titleVisibility = isVisible ? .visible : .hidden
        liveWindow.titlebarAppearsTransparent = !isVisible
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            liveWindow.standardWindowButton($0)?.isHidden = !isVisible
        }
    }

    private func updateIdleScreenTimerVisibility() {
        IdleScreenSettings.shared.showTime ? showIdleScreenTimer() : hideIdleScreenTimer()
    }

    private func showIdleScreenTimer() {
        guard idleScreenTimer == nil else { return }
        idleScreenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshIdleScreenContents()
        }

        if let timer = idleScreenTimer { RunLoop.current.add(timer, forMode: .common) }
    }

    private func hideIdleScreenTimer() {
        idleScreenTimer?.invalidate()
        idleScreenTimer = nil
    }

}

private final class CapturePreviewView: NSView {

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("CapturePreviewView requires an AVCaptureVideoPreviewLayer")
        }
        return previewLayer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        return AVCaptureVideoPreviewLayer()
    }

}
