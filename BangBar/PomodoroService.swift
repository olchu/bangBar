import Combine
import Foundation

enum PomodoroSessionType {
    case work
    case shortBreak
    case longBreak
}

final class PomodoroService: ObservableObject {
    @Published var sessionType: PomodoroSessionType = .work
    @Published var isRunning = false
    @Published var secondsRemaining = 25 * 60
    @Published var completedPomodoros = 0

    private static let completedKey = "pomodoroCompletedCount"

    private var workDuration: Int {
        max(UserDefaults.standard.integer(forKey: BangBarSettings.Key.pomodoroWorkMinutes), 1) * 60
    }

    private var shortBreakDuration: Int {
        max(UserDefaults.standard.integer(forKey: BangBarSettings.Key.pomodoroShortBreakMinutes), 1) * 60
    }

    private var longBreakDuration: Int {
        max(UserDefaults.standard.integer(forKey: BangBarSettings.Key.pomodoroLongBreakMinutes), 1) * 60
    }

    var pomodorosBeforeLongBreak: Int {
        max(UserDefaults.standard.integer(forKey: BangBarSettings.Key.pomodoroRounds), 1)
    }

    private var ticker: Timer?

    init() {
        completedPomodoros = UserDefaults.standard.integer(forKey: Self.completedKey)
        secondsRemaining = workDuration
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    deinit {
        ticker?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func duration(for type: PomodoroSessionType) -> Int {
        switch type {
        case .work: return workDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }

    @objc private func settingsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRunning else { return }
            let updated = self.duration(for: self.sessionType)
            if self.secondsRemaining != updated {
                self.secondsRemaining = updated
            }
        }
    }

    var progress: Double {
        1.0 - Double(secondsRemaining) / Double(duration(for: sessionType))
    }

    var timeString: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    var sessionLabel: String {
        switch sessionType {
        case .work: return "Work"
        case .shortBreak: return "Break"
        case .longBreak: return "Rest"
        }
    }

    func togglePlayPause() {
        isRunning ? pause() : resume()
    }

    func reset() {
        pause()
        sessionType = .work
        secondsRemaining = workDuration
    }

    func resetIncludingCycles() {
        reset()
        completedPomodoros = 0
        UserDefaults.standard.set(completedPomodoros, forKey: Self.completedKey)
    }

    private func resume() {
        ticker?.invalidate()
        isRunning = true

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func pause() {
        isRunning = false
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        secondsRemaining = max(secondsRemaining - 1, 0)
        guard secondsRemaining <= 0 else { return }
        advance()
    }

    private func advance() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false

        if sessionType == .work {
            completedPomodoros += 1
            UserDefaults.standard.set(completedPomodoros, forKey: Self.completedKey)
            let isLong = completedPomodoros % pomodorosBeforeLongBreak == 0
            sessionType = isLong ? .longBreak : .shortBreak
        } else {
            sessionType = .work
        }
        secondsRemaining = duration(for: sessionType)

        resume()
    }
}
