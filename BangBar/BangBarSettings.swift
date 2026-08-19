import Foundation
import SwiftUI

enum ClipboardButtonPosition: String, CaseIterable, Identifiable {
    case nearNotch
    case panelEdge

    var id: Self { self }

    var title: String {
        switch self {
        case .nearNotch: return "Near notch"
        case .panelEdge: return "Panel edge"
        }
    }
}

enum BangBarWidget: String, CaseIterable, Identifiable {
    case nowPlaying
    case clock
    case moon
    case pomodoro
    case reminders
    case mirror
    case system
    case github
    case aiUsage
    case companion
    case habits
    case translator
    case dayPlans

    var id: String { rawValue }

    static var visibleCases: [BangBarWidget] {
        allCases.filter { $0 != .companion }
    }

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
        case .system:
            return "System"
        case .github:
            return "GitHub"
        case .aiUsage:
            return "AI Usage"
        case .companion:
            return "Companion"
        case .habits:
            return "Habits"
        case .translator:
            return "Translator"
        case .dayPlans:
            return "Day Plans"
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
        case .system:
            return "CPU, memory, battery and local IP"
        case .github:
            return "Public contributions from the last four months"
        case .aiUsage:
            return "Codex and Claude Code quota, session and weekly"
        case .companion:
            return "A calm desktop pet that grows with active use"
        case .habits:
            return "Track daily routines and consistency"
        case .translator:
            return "Translate between Russian and English"
        case .dayPlans:
            return "Plans assigned to today, synced via iCloud Drive"
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
        case .system:
            return "widgetSystem"
        case .github:
            return "widgetGitHub"
        case .aiUsage:
            return "widgetAIUsage"
        case .companion:
            return "widgetCompanion"
        case .habits:
            return "widgetHabits"
        case .translator:
            return "widgetTranslator"
        case .dayPlans:
            return "widgetDayPlans"
        }
    }

    var layoutWidth: CGFloat {
        switch self {
        case .nowPlaying: PanelLayout.nowPlayingWidgetWidth
        case .clock: PanelLayout.clockWidgetWidth
        case .moon: PanelLayout.moonWidgetWidth
        case .pomodoro: PanelLayout.pomodoroWidgetWidth
        case .reminders: PanelLayout.remindersWidgetWidth
        case .mirror: PanelLayout.mirrorWidgetWidth
        case .system: PanelLayout.systemWidgetWidth
        case .github: PanelLayout.githubWidgetWidth
        case .aiUsage: PanelLayout.aiUsageWidgetWidth
        case .companion: PanelLayout.companionWidgetWidth
        case .habits: PanelLayout.habitsWidgetWidth
        case .translator: PanelLayout.translatorWidgetWidth
        case .dayPlans: PanelLayout.dayPlansWidgetWidth
        }
    }
}

enum BangBarSettings {
    enum Key {
        static let showNowPlayingWidget = "showNowPlayingWidget"
        static let showClockWidget = "showClockWidget"
        static let showMoonWidget = "showMoonWidget"
        static let showMirrorWidget = "showMirrorWidget"
        static let showSystemWidget = "showSystemWidget"
        static let showGitHubWidget = "showGitHubWidget"
        static let showAIUsageWidget = "showAIUsageWidget"
        static let showCompanionWidget = "showCompanionWidget"
        static let showHabitsWidget = "showHabitsWidget"
        static let showTranslatorWidget = "showTranslatorWidget"
        static let translatorSourceIsRussian = "translatorSourceIsRussian"
        static let showDayPlansWidget = "showDayPlansWidget"
        static let habitsData = "habitsData"
        static let githubUsername = "githubUsername"
        static let moonUsesCurrentLocation = "moonUsesCurrentLocation"
        static let moonLocationName = "moonLocationName"
        static let moonLatitude = "moonLatitude"
        static let moonLongitude = "moonLongitude"
        static let moonCurrentLatitude = "moonCurrentLatitude"
        static let moonCurrentLongitude = "moonCurrentLongitude"
        static let accentColorHex = "accentColorHex"
        static let tintWalkingMan = "tintWalkingMan"
        static let panelActivationThreshold = "panelActivationThreshold"
        static let showPomodoroWidget = "showPomodoroWidget"
        static let showRemindersWidget = "showRemindersWidget"
        static let reminderListId = "reminderListId"
        static let selectedCalendarIds = "selectedCalendarIds"
        static let calendarAlertsEnabled = "calendarAlertsEnabled"
        static let calendarAlertLeadMinutes = "calendarAlertLeadMinutes"
        static let calendarAlertBackgroundOpacity = "calendarAlertBackgroundOpacity"
        static let calendarAlertBlurIntensity = "calendarAlertBlurIntensity"
        static let widgetOrder = "widgetOrder"
        static let widgetPages = "widgetPages"
        static let pageSwipeInverted = "pageSwipeInverted"
        static let pomodoroWorkMinutes = "pomodoroWorkMinutes"
        static let pomodoroShortBreakMinutes = "pomodoroShortBreakMinutes"
        static let pomodoroLongBreakMinutes = "pomodoroLongBreakMinutes"
        static let pomodoroRounds = "pomodoroRounds"
        static let clipboardStorageLimitMB = "clipboardStorageLimitMB"
        static let clipboardButtonPosition = "clipboardButtonPosition"
        static let clipboardSwipeNavigationEnabled = "clipboardSwipeNavigationEnabled"
        static let clipboardSwipeNavigationInverted = "clipboardSwipeNavigationInverted"
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
            Key.showSystemWidget: false,
            Key.showGitHubWidget: false,
            Key.showAIUsageWidget: false,
            Key.showCompanionWidget: false,
            Key.showHabitsWidget: false,
            Key.showTranslatorWidget: false,
            Key.showDayPlansWidget: false,
            Key.translatorSourceIsRussian: true,
            Key.githubUsername: "",
            Key.moonUsesCurrentLocation: true,
            Key.moonLocationName: "Istanbul",
            Key.moonLatitude: 41.0082,
            Key.moonLongitude: 28.9784,
            Key.moonCurrentLatitude: 41.0082,
            Key.moonCurrentLongitude: 28.9784,
            Key.accentColorHex: defaultAccentColorHex,
            Key.tintWalkingMan: true,
            Key.panelActivationThreshold: 0,
            Key.showPomodoroWidget: true,
            Key.showRemindersWidget: true,
            Key.calendarAlertsEnabled: false,
            Key.calendarAlertLeadMinutes: 0,
            Key.calendarAlertBackgroundOpacity: 62,
            Key.calendarAlertBlurIntensity: 100,
            Key.widgetOrder: defaultWidgetOrderRaw,
            Key.widgetPages: "{}",
            Key.pageSwipeInverted: false,
            Key.pomodoroWorkMinutes: 25,
            Key.pomodoroShortBreakMinutes: 5,
            Key.pomodoroLongBreakMinutes: 15,
            Key.pomodoroRounds: 4,
            Key.clipboardStorageLimitMB: 100,
            Key.clipboardButtonPosition: ClipboardButtonPosition.nearNotch.rawValue,
            Key.clipboardSwipeNavigationEnabled: true,
            Key.clipboardSwipeNavigationInverted: false,
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

    static func widgetPages(from rawValue: String) -> [String: Int] {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func widgetPagesRaw(from pages: [String: Int]) -> String {
        guard let data = try? JSONEncoder().encode(pages),
              let raw = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return raw
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

    static var showSystemWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showSystemWidget) as? Bool ?? false
    }

    static var showGitHubWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showGitHubWidget) as? Bool ?? false
    }

    static var showAIUsageWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showAIUsageWidget) as? Bool ?? false
    }

    static var showCompanionWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showCompanionWidget) as? Bool ?? false
    }

    static var showHabitsWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showHabitsWidget) as? Bool ?? false
    }

    static var showTranslatorWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showTranslatorWidget) as? Bool ?? false
    }

    static var showDayPlansWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showDayPlansWidget) as? Bool ?? false
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
