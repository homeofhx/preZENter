import Cocoa
import Foundation

class PresenterTimer: NSObject {
    
    public var totalSeconds: Int = 0
    public var onTick: ((String) -> Void)?
    
    private var timer: Timer?
    
    public func startTimer() {
        timer?.invalidate()
        let initialTimeString = self.getTimeString()
        self.onTick?(initialTimeString)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.totalSeconds += 1
            let timeString = self.getTimeString()
            self.onTick?(timeString)
        }
        
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    public func pauseTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    public func getTimeString() -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    
}
