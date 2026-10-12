import Combine
import Foundation

struct Countdown: Codable, Equatable {
    var title: String
    var targetDate: Date
    var includesTime: Bool
    var createdAt: Date
    var updatedAt: Date
}

@MainActor
final class CountdownService: ObservableObject {
    static let shared = CountdownService()
    static let maximumTitleLength = 80

    @Published private(set) var countdown: Countdown?

    private struct StoredData: Codable {
        var version: Int
        var countdown: Countdown?
    }

    private static let storageVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func save(title: String, targetDate: Date, includesTime: Bool, calendar: Calendar = .autoupdatingCurrent) {
        let trimmed = Self.normalizedTitle(title)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        countdown = Countdown(
            title: trimmed,
            targetDate: CountdownFormatter.effectiveTarget(targetDate, includesTime: includesTime, calendar: calendar),
            includesTime: includesTime,
            createdAt: countdown?.createdAt ?? now,
            updatedAt: now
        )
        persist()
    }

    func delete() {
        countdown = nil
        persist()
    }

    static func normalizedTitle(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTitleLength))
    }

    private func load() {
        guard let data = defaults.data(forKey: BangBarSettings.Key.countdownData),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data),
              stored.version == Self.storageVersion else {
            countdown = nil
            return
        }
        countdown = stored.countdown
    }

    private func persist() {
        let stored = StoredData(version: Self.storageVersion, countdown: countdown)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: BangBarSettings.Key.countdownData)
    }
}
