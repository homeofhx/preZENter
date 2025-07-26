import Cocoa
import AVFoundation

class VideoCaptureDevs: NSObject {
    
    private var videoDevices = AVCaptureDevice.devices(for: .video)
    private var currentDevice : AVCaptureDevice!
    private var currentSession = AVCaptureSession()
    
    public func setup(popup: NSPopUpButton) {
        for device in videoDevices {
            popup.addItem(withTitle: device.localizedName)
        }
    }
    
    public func refreshDevs(popup: NSPopUpButton) {
        for _ in 1...popup.numberOfItems-1 {
            popup.removeItem(at: 1)
        }
        
        videoDevices = AVCaptureDevice.devices(for: .video)
        setup(popup: popup)
    }
    
    public func selectDev(popup: NSPopUpButton, liveWindow: LiveWindow) {
        stopVideoDevSession(liveWindow: liveWindow)
        
        for input in currentSession.inputs {
            currentSession.removeInput(input)
        }
        
        for device in videoDevices {
            if device.localizedName == popup.titleOfSelectedItem {
                currentDevice = videoDevices[popup.indexOfSelectedItem - 1]
                showLiveView(liveWindow: liveWindow)
            }
        }
    }
    
    public func stopVideoDevSession(liveWindow: LiveWindow) {
        currentSession.stopRunning()
        liveWindow.stopLiveView()
    }
    
    private func showLiveView(liveWindow: LiveWindow) {
        do {
            try currentSession.addInput(AVCaptureDeviceInput(device: currentDevice))
        } catch {
            return
        }
        
        currentSession.sessionPreset = .high
        currentSession.startRunning()
        liveWindow.setupLiveView(session: currentSession)
    }
    
}
