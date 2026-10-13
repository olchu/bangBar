import Combine
import Foundation

/// Calendar days as `yyyy-MM-dd`, the key Day Plans and Habits store their records under.
enum DayIdentifier {
    static func string(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(from identifier: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = identifier.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Fires on the main run loop whenever "today" may have changed: midnight, a time zone or a clock change.
    static var changes: AnyPublisher<Void, Never> {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange]
        return Publishers.MergeMany(names.map { center.publisher(for: $0) })
            .map { _ in () }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
