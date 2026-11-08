import Foundation

final class PresenterTimer {
    
    private(set) var totalSeconds: Int = 0
    var onTick: ((String) -> Void)?
    
    private var timer: Timer?
    
    func startTimer() {
        timer?.invalidate()
        onTick?(getTimeString())
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.totalSeconds += 1
            self.onTick?(self.getTimeString())
        }
        
        if let timer = timer { RunLoop.current.add(timer, forMode: .common) }
    }
    
    func pauseTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func getTimeString() -> String {
        String(format: "%02d:%02d:%02d", totalSeconds/3600, (totalSeconds%3600)/60, totalSeconds%60)
    }
    
}
