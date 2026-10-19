import Foundation
import SwiftUI

nonisolated enum MusicPlayer: String, CaseIterable, Identifiable {
    case spotify
    case appleMusic

    var id: Self { self }

    init?(bundleIdentifier: String?) {
        guard let player = Self.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
        self = player
    }

    var title: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    var applicationName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Music"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }
}

enum MusicVisualizerMode: String, CaseIterable, Identifiable {
    case animated
    case live

    var id: Self { self }

    var title: String {
        switch self {
        case .animated: "Animated"
        case .live: "Live"
        }
    }
}

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
    case countdown
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

    var visibilityKey: String {
        switch self {
        case .nowPlaying: BangBarSettings.Key.showNowPlayingWidget
        case .clock: BangBarSettings.Key.showClockWidget
        case .moon: BangBarSettings.Key.showMoonWidget
        case .pomodoro: BangBarSettings.Key.showPomodoroWidget
        case .countdown: BangBarSettings.Key.showCountdownWidget
        case .reminders: BangBarSettings.Key.showRemindersWidget
        case .mirror: BangBarSettings.Key.showMirrorWidget
        case .system: BangBarSettings.Key.showSystemWidget
        case .github: BangBarSettings.Key.showGitHubWidget
        case .aiUsage: BangBarSettings.Key.showAIUsageWidget
        case .companion: BangBarSettings.Key.showCompanionWidget
        case .habits: BangBarSettings.Key.showHabitsWidget
        case .translator: BangBarSettings.Key.showTranslatorWidget
        case .dayPlans: BangBarSettings.Key.showDayPlansWidget
        }
    }

    var isVisibleByDefault: Bool {
        switch self {
        case .nowPlaying, .clock, .moon, .pomodoro, .reminders, .mirror: true
        case .countdown, .system, .github, .aiUsage, .companion, .habits, .translator, .dayPlans: false
        }
    }

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
        case .countdown:
            return "Countdown"
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
        case .countdown:
            return "Time left until a date you pick"
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

    enum Icon {
        case asset(String)
        case symbol(String)
    }

    var icon: Icon {
        switch self {
        case .nowPlaying: .asset("widgetMusic")
        case .clock: .asset("widgetCalendar")
        case .moon: .asset("widgetMoon")
        case .pomodoro: .asset("widgetFocus")
        case .countdown: .asset("widgetCountdown")
        case .reminders: .asset("widgetReminders")
        case .mirror: .asset("widgetMirror")
        case .system: .asset("widgetSystem")
        case .github: .symbol("chevron.left.forwardslash.chevron.right")
        case .aiUsage: .symbol("gauge.with.dots.needle.67percent")
        case .companion: .asset("widgetCompanion")
        case .habits: .asset("widgetHabits")
        case .translator: .asset("widgetTranslator")
        case .dayPlans: .symbol("list.bullet.clipboard")
        }
    }

    var layoutWidth: CGFloat {
        switch self {
        case .nowPlaying: PanelLayout.nowPlayingWidgetWidth
        case .clock: PanelLayout.clockWidgetWidth
        case .moon: PanelLayout.moonWidgetWidth
        case .pomodoro: PanelLayout.pomodoroWidgetWidth
        case .countdown: PanelLayout.countdownWidgetWidth
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

enum KeyboardSwitcherTrigger: String, CaseIterable, Identifiable {
    case doubleShift
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .doubleShift: return "Double Shift"
        case .custom: return "Custom shortcut"
        }
    }
}

enum BangBarSettings {
    enum Key {
        static let showNowPlayingWidget = "showNowPlayingWidget"
        static let preferredMusicPlayer = "preferredMusicPlayer"
        static let musicVisualizerMode = "musicVisualizerMode"
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
        static let liveActivityPowerEnabled = "liveActivityPowerEnabled"
        static let liveActivityAudioEnabled = "liveActivityAudioEnabled"
        static let liveActivityVolumeEnabled = "liveActivityVolumeEnabled"
        static let volumeHUDReplacesSystem = "volumeHUDReplacesSystem"
        static let volumeKeyInterceptionFailedOSMajor = "volumeKeyInterceptionFailedOSMajor"
        static let showPomodoroWidget = "showPomodoroWidget"
        static let showCountdownWidget = "showCountdownWidget"
        static let countdownData = "countdownData"
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
        static let keyboardSwitcherEnabled = "keyboardSwitcherEnabled"
        static let keyboardSwitcherTrigger = "keyboardSwitcherTrigger"
        static let keyboardSwitcherShortcutKeyCode = "keyboardSwitcherShortcutKeyCode"
        static let keyboardSwitcherShortcutModifiers = "keyboardSwitcherShortcutModifiers"
        static let keyboardSwitcherShortcutLabel = "keyboardSwitcherShortcutLabel"
        static let keyboardSwitcherAutoEnabled = "keyboardSwitcherAutoEnabled"
        static let keyboardSwitcherShowsNotice = "keyboardSwitcherShowsNotice"
        static let keyboardSwitcherExcludedApps = "keyboardSwitcherExcludedApps"
        static let keyboardSwitcherExceptions = "keyboardSwitcherExceptions"
        static let keyboardSwitcherLearnedWords = "keyboardSwitcherLearnedWords"
        static let keyboardSwitcherUndoCounts = "keyboardSwitcherUndoCounts"
    }

    static let defaultAccentColorHex = "#FF383C"
    static let defaultKeyboardSwitcherExcludedApps = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode"
    ].joined(separator: "\n")
    static let defaultWidgetOrderRaw = widgetOrderRaw(from: BangBarWidget.allCases)
    static let defaultCalendarAlertBlurRadius = 32
    static let calendarAlertBlurRadiusRange = 0...80

    static func registerDefaults() {
        var defaults: [String: Any] = [
            Key.preferredMusicPlayer: MusicPlayer.appleMusic.rawValue,
            Key.musicVisualizerMode: MusicVisualizerMode.animated.rawValue,
            Key.translatorSourceIsRussian: true,
            Key.githubUsername: "",
            Key.moonUsesCurrentLocation: true,
            Key.moonLocationName: "Istanbul",
            Key.moonLatitude: 41.0082,
            Key.moonLongitude: 28.9784,
            Key.accentColorHex: defaultAccentColorHex,
            Key.tintWalkingMan: true,
            Key.panelActivationThreshold: 0,
            Key.liveActivityPowerEnabled: true,
            Key.liveActivityAudioEnabled: true,
            Key.liveActivityVolumeEnabled: true,
            Key.volumeHUDReplacesSystem: true,
            Key.calendarAlertsEnabled: false,
            Key.calendarAlertLeadMinutes: 0,
            Key.calendarAlertBackgroundOpacity: 62,
            Key.calendarAlertBlurIntensity: defaultCalendarAlertBlurRadius,
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
            Key.clipboardIgnoreShortcutGraceMS: 1500,
            Key.keyboardSwitcherEnabled: false,
            Key.keyboardSwitcherTrigger: KeyboardSwitcherTrigger.doubleShift.rawValue,
            Key.keyboardSwitcherShortcutKeyCode: -1,
            Key.keyboardSwitcherShortcutModifiers: 0,
            Key.keyboardSwitcherShortcutLabel: "Not set",
            Key.keyboardSwitcherAutoEnabled: false,
            Key.keyboardSwitcherShowsNotice: true,
            Key.keyboardSwitcherExcludedApps: defaultKeyboardSwitcherExcludedApps,
            Key.keyboardSwitcherExceptions: "",
            Key.keyboardSwitcherLearnedWords: "",
            Key.keyboardSwitcherUndoCounts: ""
        ]
        for widget in BangBarWidget.allCases {
            defaults[widget.visibilityKey] = widget.isVisibleByDefault
        }
        UserDefaults.standard.register(defaults: defaults)
    }

    static func isWidgetVisible(_ widget: BangBarWidget) -> Bool {
        BangBarWidget.visibleCases.contains(widget) && UserDefaults.standard.bool(forKey: widget.visibilityKey)
    }

    static var keyboardSwitcherExcludedApps: [String] {
        get { lines(forKey: Key.keyboardSwitcherExcludedApps) }
        set { UserDefaults.standard.set(newValue.joined(separator: "\n"), forKey: Key.keyboardSwitcherExcludedApps) }
    }

    static var keyboardSwitcherExceptions: Set<String> {
        get { Set(lines(forKey: Key.keyboardSwitcherExceptions)) }
        set { UserDefaults.standard.set(newValue.sorted().joined(separator: "\n"), forKey: Key.keyboardSwitcherExceptions) }
    }

    /// How many times each typed word's automatic switch was undone, as `word<TAB>count` lines.
    static var keyboardSwitcherUndoCounts: [String: Int] {
        get {
            let entries = lines(forKey: Key.keyboardSwitcherUndoCounts).compactMap { line -> (String, Int)? in
                let parts = line.split(separator: "\t")
                guard parts.count == 2, let count = Int(parts[1]) else { return nil }
                return (String(parts[0]), count)
            }
            return Dictionary(entries, uniquingKeysWith: max)
        }
        set {
            let raw = newValue.sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
            UserDefaults.standard.set(raw, forKey: Key.keyboardSwitcherUndoCounts)
        }
    }

    static var keyboardSwitcherLearnedWords: KeyboardLearnedWords {
        get { KeyboardLearnedWords(rawValue: UserDefaults.standard.string(forKey: Key.keyboardSwitcherLearnedWords) ?? "") }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.keyboardSwitcherLearnedWords) }
    }

    static func lines(_ rawValue: String) -> [String] {
        rawValue.split(separator: "\n").map(String.init)
    }

    private static func lines(forKey key: String) -> [String] {
        lines(UserDefaults.standard.string(forKey: key) ?? "")
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

    private static var lastDecodedWidgetPages: (rawValue: String, pages: [String: Int])?

    /// Called several times per panel render and on every scroll event; the raw value rarely changes.
    static func widgetPages(from rawValue: String) -> [String: Int] {
        if let cached = lastDecodedWidgetPages, cached.rawValue == rawValue {
            return cached.pages
        }
        let pages = rawValue.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        lastDecodedWidgetPages = (rawValue, pages)
        return pages
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

    static var preferredMusicPlayer: MusicPlayer {
        guard let rawValue = UserDefaults.standard.string(forKey: Key.preferredMusicPlayer) else {
            return .appleMusic
        }
        return MusicPlayer(rawValue: rawValue) ?? .appleMusic
    }

    /// Recorded when the system turned out to handle the volume keys itself; a new major macOS earns another try.
    static func isVolumeKeyInterceptionUnsupported(failedMajorVersion: Int) -> Bool {
        failedMajorVersion == ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    static var isVolumeKeyInterceptionUnsupported: Bool {
        isVolumeKeyInterceptionUnsupported(
            failedMajorVersion: UserDefaults.standard.integer(forKey: Key.volumeKeyInterceptionFailedOSMajor)
        )
    }

    static func markVolumeKeyInterceptionUnsupported() {
        UserDefaults.standard.set(
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            forKey: Key.volumeKeyInterceptionFailedOSMajor
        )
    }

    static var panelActivationThreshold: CGFloat {
        CGFloat(UserDefaults.standard.integer(forKey: Key.panelActivationThreshold))
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

/// Key paths for KVO on single settings; each property name must equal its defaults key.
extension UserDefaults {
    @objc dynamic var liveActivityVolumeEnabled: Bool {
        bool(forKey: BangBarSettings.Key.liveActivityVolumeEnabled)
    }

    @objc dynamic var volumeHUDReplacesSystem: Bool {
        bool(forKey: BangBarSettings.Key.volumeHUDReplacesSystem)
    }
}
