import Foundation
import SwiftUI

enum BangBarWidget: String, CaseIterable, Identifiable {
    case nowPlaying
    case clock
    case moon
    case pomodoro
    case reminders
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying:
            return "Music"
        case .clock:
            return "Clock & Calendar"
        case .moon:
            return "Moon"
        case .pomodoro:
            return "Pomodoro"
        case .reminders:
            return "Reminders"
        case .mirror:
            return "Mirror"
        }
    }

    var subtitle: String {
        switch self {
        case .nowPlaying:
            return "Control your music playback"
        case .clock:
            return "Time, date and upcoming events"
        case .moon:
            return "Moon phase and cycle"
        case .pomodoro:
            return "Focus timer and sessions"
        case .reminders:
            return "Today's tasks and overdue"
        case .mirror:
            return "Quick mirror access"
        }
    }

    var systemImage: String {
        switch self {
        case .nowPlaying:
            return "music.note"
        case .clock:
            return "calendar"
        case .moon:
            return "moon"
        case .pomodoro:
            return "stopwatch"
        case .reminders:
            return "bell.badge"
        case .mirror:
            return "rectangle.portrait"
        }
    }
}

enum BangBarSettings {
    enum Key {
        static let showNowPlayingWidget = "showNowPlayingWidget"
        static let showClockWidget = "showClockWidget"
        static let showMoonWidget = "showMoonWidget"
        static let showMirrorWidget = "showMirrorWidget"
        static let accentColorHex = "accentColorHex"
        static let tintWalkingMan = "tintWalkingMan"
        static let showPomodoroWidget = "showPomodoroWidget"
        static let showRemindersWidget = "showRemindersWidget"
        static let reminderListId = "reminderListId"
        static let selectedCalendarIds = "selectedCalendarIds"
        static let widgetOrder = "widgetOrder"
        static let pomodoroWorkMinutes = "pomodoroWorkMinutes"
        static let pomodoroShortBreakMinutes = "pomodoroShortBreakMinutes"
        static let pomodoroLongBreakMinutes = "pomodoroLongBreakMinutes"
        static let pomodoroRounds = "pomodoroRounds"
    }

    static let defaultAccentColorHex = "#FF383C"
    static let defaultWidgetOrderRaw = widgetOrderRaw(from: BangBarWidget.allCases)

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showNowPlayingWidget: true,
            Key.showClockWidget: true,
            Key.showMoonWidget: true,
            Key.showMirrorWidget: true,
            Key.accentColorHex: defaultAccentColorHex,
            Key.tintWalkingMan: true,
            Key.showPomodoroWidget: true,
            Key.showRemindersWidget: true,
            Key.widgetOrder: defaultWidgetOrderRaw,
            Key.pomodoroWorkMinutes: 25,
            Key.pomodoroShortBreakMinutes: 5,
            Key.pomodoroLongBreakMinutes: 15,
            Key.pomodoroRounds: 4
        ])
    }

    static func widgetOrder(from rawValue: String) -> [BangBarWidget] {
        let decoded = rawValue
            .split(separator: ",")
            .compactMap { BangBarWidget(rawValue: String($0)) }

        var ordered: [BangBarWidget] = []
        for widget in decoded where !ordered.contains(widget) {
            ordered.append(widget)
        }

        for widget in BangBarWidget.allCases where !ordered.contains(widget) {
            ordered.append(widget)
        }

        return ordered
    }

    static func widgetOrderRaw(from widgets: [BangBarWidget]) -> String {
        widgets.map(\.rawValue).joined(separator: ",")
    }

    static func selectedCalendarIds(from rawValue: String) -> [String]? {
        guard !rawValue.isEmpty else { return nil }

        if let data = rawValue.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids
        }

        return rawValue
            .split(separator: ",")
            .map { String($0) }
    }

    static func selectedCalendarIdsRaw(from ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids),
              let rawValue = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return rawValue
    }

    static var showNowPlayingWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showNowPlayingWidget) as? Bool ?? true
    }

    static var showClockWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showClockWidget) as? Bool ?? true
    }

    static var showMoonWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showMoonWidget) as? Bool ?? true
    }

    static var showMirrorWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showMirrorWidget) as? Bool ?? true
    }

    static var showPomodoroWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showPomodoroWidget) as? Bool ?? true
    }

    static var showRemindersWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showRemindersWidget) as? Bool ?? true
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}
