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
            return "Focus Timer"
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

    var iconAsset: String {
        switch self {
        case .nowPlaying:
            return "widgetMusic"
        case .clock:
            return "widgetCalendar"
        case .moon:
            return "widgetMoon"
        case .pomodoro:
            return "widgetFocus"
        case .reminders:
            return "widgetReminders"
        case .mirror:
            return "widgetMirror"
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
        static let panelActivationThreshold = "panelActivationThreshold"
        static let showPomodoroWidget = "showPomodoroWidget"
        static let showRemindersWidget = "showRemindersWidget"
        static let reminderListId = "reminderListId"
        static let selectedCalendarIds = "selectedCalendarIds"
        static let widgetOrder = "widgetOrder"
        static let pomodoroWorkMinutes = "pomodoroWorkMinutes"
        static let pomodoroShortBreakMinutes = "pomodoroShortBreakMinutes"
        static let pomodoroLongBreakMinutes = "pomodoroLongBreakMinutes"
        static let pomodoroRounds = "pomodoroRounds"
        static let clipboardStorageLimitMB = "clipboardStorageLimitMB"
        static let clipboardIgnoreTransientChanges = "clipboardIgnoreTransientChanges"
        static let clipboardTransientDelayMS = "clipboardTransientDelayMS"
        static let clipboardIgnoreShortcutEnabled = "clipboardIgnoreShortcutEnabled"
        static let clipboardIgnoreShortcutKeyCode = "clipboardIgnoreShortcutKeyCode"
        static let clipboardIgnoreShortcutModifiers = "clipboardIgnoreShortcutModifiers"
        static let clipboardIgnoreShortcutLabel = "clipboardIgnoreShortcutLabel"
        static let clipboardIgnoreShortcutGraceMS = "clipboardIgnoreShortcutGraceMS"
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
            Key.panelActivationThreshold: 0,
            Key.showPomodoroWidget: true,
            Key.showRemindersWidget: true,
            Key.widgetOrder: defaultWidgetOrderRaw,
            Key.pomodoroWorkMinutes: 25,
            Key.pomodoroShortBreakMinutes: 5,
            Key.pomodoroLongBreakMinutes: 15,
            Key.pomodoroRounds: 4,
            Key.clipboardStorageLimitMB: 100,
            Key.clipboardIgnoreTransientChanges: true,
            Key.clipboardTransientDelayMS: 1000,
            Key.clipboardIgnoreShortcutEnabled: false,
            Key.clipboardIgnoreShortcutKeyCode: -1,
            Key.clipboardIgnoreShortcutModifiers: 0,
            Key.clipboardIgnoreShortcutLabel: "Not set",
            Key.clipboardIgnoreShortcutGraceMS: 1500
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

    static var panelActivationThreshold: CGFloat {
        CGFloat(UserDefaults.standard.integer(forKey: Key.panelActivationThreshold))
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

    static var clipboardStorageLimitMB: Int {
        UserDefaults.standard.object(forKey: Key.clipboardStorageLimitMB) as? Int ?? 100
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
