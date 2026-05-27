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
    @Published var didJustComplete = false

    private static let completedKey = "pomodoroCompletedCount"
    static let workDuration = 25 * 60
    static let shortBreakDuration = 5 * 60
    static let longBreakDuration = 15 * 60
    private static let pomodorosBeforeLongBreak = 4

    private var ticker: Timer?

    init() {
        completedPomodoros = UserDefaults.standard.integer(forKey: Self.completedKey)
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
        secondsRemaining = Self.workDuration
        didJustComplete = false
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

        didJustComplete = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.didJustComplete = false
        }

        if sessionType == .work {
            completedPomodoros += 1
            UserDefaults.standard.set(completedPomodoros, forKey: Self.completedKey)
            let isLong = completedPomodoros % Self.pomodorosBeforeLongBreak == 0
            sessionType = isLong ? .longBreak : .shortBreak
            secondsRemaining = isLong ? Self.longBreakDuration : Self.shortBreakDuration
        } else {
            sessionType = .work
            secondsRemaining = Self.workDuration
        }

        resume()
    }
}
