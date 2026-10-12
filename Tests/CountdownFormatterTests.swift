import Foundation

@main
struct CountdownFormatterTests {
    static func main() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        // Long ranges show years, months and days; hours are dropped.
        check(utc, now: (2026, 1, 1, 12, 0), target: (2028, 4, 5, 18, 0), time: true, "2y 3m 4d")
        check(utc, now: (2026, 1, 1, 0, 0), target: (2027, 1, 5, 0, 0), time: true, "1y 4d")
        check(utc, now: (2026, 1, 1, 0, 0), target: (2026, 3, 1, 9, 0), time: true, "2m")
        check(utc, now: (2026, 5, 10, 8, 0), target: (2027, 7, 12, 0, 0), time: false, "1y 2m 2d")
        print("PASS: years, months and days")

        // Under a month shows days and hours.
        check(utc, now: (2026, 3, 1, 0, 0), target: (2026, 3, 15, 6, 0), time: true, "14d 6h")
        check(utc, now: (2026, 3, 1, 10, 0), target: (2026, 3, 15, 10, 0), time: true, "14d")
        check(utc, now: (2026, 3, 1, 22, 0), target: (2026, 3, 2, 23, 30), time: true, "1d 1h")
        print("PASS: under a month")

        // Under a day shows hours and minutes.
        check(utc, now: (2026, 3, 1, 10, 0), target: (2026, 3, 1, 16, 20), time: true, "6h 20m")
        check(utc, now: (2026, 3, 1, 22, 0), target: (2026, 3, 2, 3, 0), time: true, "5h")
        check(utc, now: (2026, 3, 1, 10, 0), target: (2026, 3, 1, 10, 20), time: true, "20m")
        let almostThere = date(utc, (2026, 3, 1, 10, 0)).addingTimeInterval(-30)
        expect(
            CountdownFormatter.remaining(
                now: almostThere,
                target: date(utc, (2026, 3, 1, 10, 0)),
                includesTime: true,
                calendar: utc
            ),
            .lessThanMinute
        )
        print("PASS: under a day")

        // Date-only targets count calendar days and never show hours.
        check(utc, now: (2026, 3, 1, 22, 0), target: (2026, 3, 2, 0, 0), time: false, "1d")
        check(utc, now: (2026, 3, 1, 8, 0), target: (2026, 3, 15, 17, 45), time: false, "14d")
        check(utc, now: (2026, 3, 1, 23, 59), target: (2027, 3, 1, 0, 0), time: false, "1y")
        print("PASS: date-only targets")

        // Exactly now, the past, and a date-only target on the current day are done.
        check(utc, now: (2026, 3, 1, 10, 0), target: (2026, 3, 1, 10, 0), time: true, "done")
        check(utc, now: (2026, 3, 1, 10, 1), target: (2026, 3, 1, 10, 0), time: true, "done")
        check(utc, now: (2026, 3, 1, 0, 0), target: (2026, 3, 1, 0, 0), time: false, "done")
        check(utc, now: (2026, 3, 1, 8, 0), target: (2026, 3, 1, 23, 0), time: false, "done")
        check(utc, now: (2026, 3, 1, 8, 0), target: (2025, 12, 25, 0, 0), time: false, "done")
        precondition(
            CountdownFormatter.isElapsed(
                now: date(utc, (2026, 3, 1, 8, 0)),
                target: date(utc, (2026, 3, 1, 23, 0)),
                includesTime: false,
                calendar: utc
            )
        )
        precondition(
            !CountdownFormatter.isElapsed(
                now: date(utc, (2026, 3, 1, 8, 0)),
                target: date(utc, (2026, 3, 1, 23, 0)),
                includesTime: true,
                calendar: utc
            )
        )
        print("PASS: now and past are done")

        // Month ends follow Calendar clamping: Jan 31 + 1 month is the last day of February.
        check(utc, now: (2026, 1, 31, 0, 0), target: (2026, 2, 28, 0, 0), time: false, "1m")
        check(utc, now: (2026, 1, 31, 0, 0), target: (2026, 3, 1, 0, 0), time: false, "1m 1d")
        check(utc, now: (2026, 1, 31, 0, 0), target: (2026, 3, 31, 0, 0), time: false, "2m")
        check(utc, now: (2026, 3, 31, 0, 0), target: (2026, 4, 30, 0, 0), time: false, "1m")
        check(utc, now: (2028, 1, 31, 0, 0), target: (2028, 2, 29, 0, 0), time: false, "1m")
        check(utc, now: (2028, 2, 29, 0, 0), target: (2029, 3, 1, 0, 0), time: false, "1y 1d")
        check(utc, now: (2026, 2, 1, 0, 0), target: (2026, 2, 28, 12, 0), time: true, "27d 12h")
        check(utc, now: (2026, 12, 31, 23, 0), target: (2027, 1, 1, 1, 30), time: true, "2h 30m")
        print("PASS: month-end edges")

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        check(berlin, now: (2026, 3, 28, 23, 0), target: (2026, 3, 30, 0, 0), time: false, "2d")
        check(berlin, now: (2026, 10, 24, 12, 0), target: (2026, 10, 26, 0, 0), time: false, "2d")
        print("PASS: date-only across daylight-saving changes")
    }

    private typealias Moment = (year: Int, month: Int, day: Int, hour: Int, minute: Int)

    private static func date(_ calendar: Calendar, _ moment: Moment) -> Date {
        let components = DateComponents(
            year: moment.year,
            month: moment.month,
            day: moment.day,
            hour: moment.hour,
            minute: moment.minute
        )
        guard let date = calendar.date(from: components) else {
            preconditionFailure("Invalid date \(moment)")
        }
        return date
    }

    private static func check(
        _ calendar: Calendar,
        now: Moment,
        target: Moment,
        time: Bool,
        _ expected: String
    ) {
        let actual = CountdownFormatter.remaining(
            now: date(calendar, now),
            target: date(calendar, target),
            includesTime: time,
            calendar: calendar
        ).text
        precondition(actual == expected, "\(now) -> \(target) (time: \(time)): expected \(expected), got \(actual)")
    }

    private static func expect(_ actual: CountdownRemaining, _ expected: CountdownRemaining) {
        precondition(actual == expected, "Expected \(expected), got \(actual)")
    }
}
