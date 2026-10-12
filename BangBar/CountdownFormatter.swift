import Foundation

struct CountdownPart: Equatable {
    let value: Int
    let unit: String
}

enum CountdownRemaining: Equatable {
    case done
    case lessThanMinute
    case parts([CountdownPart])

    var text: String {
        switch self {
        case .done:
            return "done"
        case .lessThanMinute:
            return "<1m"
        case .parts(let parts):
            return parts.map { "\($0.value)\($0.unit)" }.joined(separator: " ")
        }
    }
}

enum CountdownFormatter {
    static func effectiveTarget(_ target: Date, includesTime: Bool, calendar: Calendar) -> Date {
        includesTime ? target : calendar.startOfDay(for: target)
    }

    static func isElapsed(now: Date, target: Date, includesTime: Bool, calendar: Calendar) -> Bool {
        now >= effectiveTarget(target, includesTime: includesTime, calendar: calendar)
    }

    static func remaining(now: Date, target: Date, includesTime: Bool, calendar: Calendar) -> CountdownRemaining {
        guard !isElapsed(now: now, target: target, includesTime: includesTime, calendar: calendar) else {
            return .done
        }

        // Date-only targets count whole calendar days, so "tomorrow" reads 1d even late in the evening.
        let start = includesTime ? now : calendar.startOfDay(for: now)
        let end = effectiveTarget(target, includesTime: includesTime, calendar: calendar)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start, to: end)
        let years = c.year ?? 0
        let months = c.month ?? 0
        let days = c.day ?? 0
        let hours = c.hour ?? 0
        let minutes = c.minute ?? 0

        let candidates: [CountdownPart]
        if years > 0 || months > 0 || !includesTime {
            candidates = [
                CountdownPart(value: years, unit: "y"),
                CountdownPart(value: months, unit: "m"),
                CountdownPart(value: days, unit: "d")
            ]
        } else if days > 0 {
            candidates = [
                CountdownPart(value: days, unit: "d"),
                CountdownPart(value: hours, unit: "h")
            ]
        } else {
            candidates = [
                CountdownPart(value: hours, unit: "h"),
                CountdownPart(value: minutes, unit: "m")
            ]
        }

        let parts = candidates.filter { $0.value > 0 }
        return parts.isEmpty ? .lessThanMinute : .parts(parts)
    }
}
