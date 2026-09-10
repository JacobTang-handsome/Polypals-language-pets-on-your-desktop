import Foundation

@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0
    var onCompletion: (() -> Void)?

    private var timer: Timer?
    private var targetDate: Date?

    init() {
        if let stored = UserDefaults.standard.object(forKey: "focusTimerTargetDate") as? Date,
           stored.timeIntervalSinceNow > 0 {
            targetDate = stored
            remaining = stored.timeIntervalSinceNow
            isRunning = true
            startTicker()
        } else {
            UserDefaults.standard.removeObject(forKey: "focusTimerTargetDate")
        }
    }

    func start(minutes: Int) {
        stop()
        remaining = TimeInterval(max(1, minutes) * 60)
        targetDate = Date().addingTimeInterval(remaining)
        UserDefaults.standard.set(targetDate, forKey: "focusTimerTargetDate")
        isRunning = true
        startTicker()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        targetDate = nil
        UserDefaults.standard.removeObject(forKey: "focusTimerTargetDate")
        isRunning = false
        remaining = 0
    }

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let targetDate else { return }
        remaining = max(0, targetDate.timeIntervalSinceNow)
        if remaining <= 0 {
            timer?.invalidate()
            timer = nil
            self.targetDate = nil
            isRunning = false
            onCompletion?()
        }
    }

    var formattedRemaining: String {
        let value = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
