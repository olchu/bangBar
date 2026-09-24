import AVFoundation
import AppKit
import Carbon
import CoreLocation
import EventKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let bangBarSettingsWillOpen = Notification.Name("bangBarSettingsWillOpen")
}

struct SettingsView: View {
    @ObservedObject var clipboardHistory: ClipboardHistoryService
    @AppStorage(BangBarSettings.Key.showNowPlayingWidget) private var showNowPlayingWidget = true
    @AppStorage(BangBarSettings.Key.preferredMusicPlayer)
    private var preferredMusicPlayerRaw = MusicPlayer.appleMusic.rawValue
    @AppStorage(BangBarSettings.Key.musicVisualizerMode)
    private var musicVisualizerModeRaw = MusicVisualizerMode.animated.rawValue
    @AppStorage(BangBarSettings.Key.showClockWidget) private var showClockWidget = true
    @AppStorage(BangBarSettings.Key.showMoonWidget) private var showMoonWidget = true
    @AppStorage(BangBarSettings.Key.showMirrorWidget) private var showMirrorWidget = true
    @AppStorage(BangBarSettings.Key.showSystemWidget) private var showSystemWidget = false
    @AppStorage(BangBarSettings.Key.showGitHubWidget) private var showGitHubWidget = false
    @AppStorage(BangBarSettings.Key.showAIUsageWidget) private var showAIUsageWidget = false
    @AppStorage(BangBarSettings.Key.showCompanionWidget) private var showCompanionWidget = false
    @AppStorage(BangBarSettings.Key.showHabitsWidget) private var showHabitsWidget = false
    @AppStorage(BangBarSettings.Key.showTranslatorWidget) private var showTranslatorWidget = false
    @AppStorage(BangBarSettings.Key.showDayPlansWidget) private var showDayPlansWidget = false
    @AppStorage(BangBarSettings.Key.githubUsername) private var githubUsername = ""
    @AppStorage(BangBarSettings.Key.moonUsesCurrentLocation) private var moonUsesCurrentLocation = true
    @AppStorage(BangBarSettings.Key.moonLocationName) private var moonLocationName = "Istanbul"
    @AppStorage(BangBarSettings.Key.showPomodoroWidget) private var showPomodoroWidget = true
    @AppStorage(BangBarSettings.Key.showRemindersWidget) private var showRemindersWidget = true
    @AppStorage(BangBarSettings.Key.reminderListId) private var reminderListId = ""
    @AppStorage(BangBarSettings.Key.selectedCalendarIds) private var selectedCalendarIdsRaw = ""
    @AppStorage(BangBarSettings.Key.calendarAlertsEnabled) private var calendarAlertsEnabled = false
    @AppStorage(BangBarSettings.Key.calendarAlertLeadMinutes) private var calendarAlertLeadMinutes = 0
    @AppStorage(BangBarSettings.Key.calendarAlertBackgroundOpacity)
    private var calendarAlertBackgroundOpacity = 62
    @AppStorage(BangBarSettings.Key.calendarAlertBlurIntensity)
    private var calendarAlertBlurIntensity = BangBarSettings.defaultCalendarAlertBlurRadius
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @AppStorage(BangBarSettings.Key.tintWalkingMan) private var tintWalkingMan = true
    @AppStorage(BangBarSettings.Key.panelActivationThreshold) private var panelActivationThreshold = 0
    @AppStorage(BangBarSettings.Key.widgetOrder) private var widgetOrderRaw = BangBarSettings.defaultWidgetOrderRaw
    @AppStorage(BangBarSettings.Key.widgetPages) private var widgetPagesRaw = "{}"
    @AppStorage(BangBarSettings.Key.pageSwipeInverted) private var pageSwipeInverted = false
    @AppStorage(BangBarSettings.Key.pomodoroWorkMinutes) private var pomodoroWorkMinutes = 25
    @AppStorage(BangBarSettings.Key.pomodoroShortBreakMinutes) private var pomodoroShortBreakMinutes = 5
    @AppStorage(BangBarSettings.Key.pomodoroLongBreakMinutes) private var pomodoroLongBreakMinutes = 15
    @AppStorage(BangBarSettings.Key.pomodoroRounds) private var pomodoroRounds = 4
    @AppStorage(BangBarSettings.Key.clipboardStorageLimitMB) private var clipboardStorageLimitMB = 100
    @AppStorage(BangBarSettings.Key.clipboardButtonPosition) private var clipboardButtonPositionRaw = ClipboardButtonPosition.nearNotch.rawValue
    @AppStorage(BangBarSettings.Key.clipboardSwipeNavigationEnabled) private var clipboardSwipeNavigationEnabled = true
    @AppStorage(BangBarSettings.Key.clipboardSwipeNavigationInverted) private var clipboardSwipeNavigationInverted = false
    @AppStorage(BangBarSettings.Key.clipboardIgnoreTransientChanges) private var clipboardIgnoreTransientChanges = true
    @AppStorage(BangBarSettings.Key.clipboardTransientDelayMS) private var clipboardTransientDelayMS = 1000
    @AppStorage(BangBarSettings.Key.clipboardIgnoreShortcutEnabled) private var clipboardIgnoreShortcutEnabled = false
    @AppStorage(BangBarSettings.Key.clipboardIgnoreShortcutKeyCode) private var clipboardIgnoreShortcutKeyCode = -1
    @AppStorage(BangBarSettings.Key.clipboardIgnoreShortcutModifiers) private var clipboardIgnoreShortcutModifiers = 0
    @AppStorage(BangBarSettings.Key.clipboardIgnoreShortcutLabel) private var clipboardIgnoreShortcutLabel = "Not set"
    @AppStorage(BangBarSettings.Key.clipboardIgnoreShortcutGraceMS) private var clipboardIgnoreShortcutGraceMS = 1500
    @State private var selectedSettingsTab = SettingsTab.widgets
    @State private var selectedWidgetTab = WidgetConfigurationTab.general
    @State private var widgetOrder = BangBarWidget.visibleCases
    @State private var widgetPages: [String: Int] = [:]
    @State private var draggedWidget: BangBarWidget?
    @StateObject private var habits = HabitService.shared
    @StateObject private var dayPlans = DayPlanService.shared

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentColorHex) },
            set: { accentColorHex = $0.hexString }
        )
    }

    var body: some View {
        let accentColor = Color(hex: accentColorHex)

        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                SettingsSidebar(selectedTab: $selectedSettingsTab, accentColor: accentColor)
                    .frame(width: 240)

                Rectangle()
                    .fill(SettingsTheme.border)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                mainContent(accentColor: accentColor)
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(SettingsTheme.primaryText)
        .background(SettingsTheme.background)
        .containerBackground(SettingsTheme.background, for: .window)
        .frame(width: 1180, height: 700)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            loadWidgetOrder()
            loadWidgetPages()
            dayPlans.reload()
        }
        .onChange(of: widgetOrderRaw) { _, _ in
            loadWidgetOrder()
        }
        .onChange(of: widgetPagesRaw) { _, _ in
            loadWidgetPages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bangBarSettingsWillOpen)) { _ in
            selectedSettingsTab = .widgets
            selectedWidgetTab = .general
            dayPlans.reload()
        }
    }

    private var titleBar: some View {
        Color.clear
            .frame(height: 48)
    }

    @ViewBuilder
    private func mainContent(accentColor: Color) -> some View {
        switch selectedSettingsTab {
        case .widgets:
            singleColumnContent(title: "WIDGETS", accentColor: accentColor) {
                widgetsSection(accentColor: accentColor)
                    .frame(width: 884)
            }
        case .permissions:
            singleColumnContent(title: "PERMISSIONS", accentColor: accentColor) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("LAUNCH")
                        LaunchAtLoginSettingsRow(accentColor: accentColor)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("ACCESS")
                        PrivacySettingsSection()
                    }
                }
                .frame(width: 884)
            }
        case .appearance:
            singleColumnContent(title: "APPEARANCE", accentColor: accentColor) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("APPEARANCE")
                        appearanceCard(accentColor: accentColor)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("INTERACTION")
                        SettingsCard {
                            SettingsStepperRow(
                                title: "Panel activation area",
                                value: $panelActivationThreshold,
                                range: -20...40,
                                unit: "px",
                                resetValue: 0,
                                accentColor: accentColor
                            )
                        }
                    }
                }
                .frame(width: 884)
            }
        case .clipboard:
            singleColumnContent(title: "CLIPBOARD", accentColor: accentColor) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("APPEARANCE")
                        clipboardAppearanceCard(accentColor: accentColor)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("GESTURES")
                        clipboardGesturesCard(accentColor: accentColor)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("STORAGE")
                        clipboardSettingsCard(accentColor: accentColor)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("TEMPORARY CHANGES")
                        clipboardTemporaryChangesCard(accentColor: accentColor)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("TRANSCRIPTION")
                        clipboardTranscriptionCard(accentColor: accentColor)
                    }
                }
                .frame(width: 884)
            }
        case .about:
            singleColumnContent(title: "ABOUT", accentColor: accentColor) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("BangBar")
                            .font(SettingsTheme.sectionTitleFont)
                            .foregroundStyle(SettingsTheme.primaryText)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("The notch takes a strip of your screen and gives nothing back. BangBar puts that space to work.")

                            Text("Move your cursor up to the notch and a small panel drops down: what's playing, your next event, today's reminders, the moon, a focus timer. Take a look, do the thing, get back to work. It hides again the second you move away.")

                            Text("Made by Olchu Studio. It lives in the menu bar and stays out of the way. No dock icon, no account, nothing to sign into.")
                        }
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                        SettingsDivider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Run into a bug, or want a widget that isn't here yet? Send it my way:")
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundStyle(SettingsTheme.secondaryText)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(verbatim: "ochurkin@gmail.com")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accentColor)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                .onTapGesture {
                                    if let url = URL(string: "mailto:ochurkin@gmail.com") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .frame(width: 884)
            }
        }
    }

    private func singleColumnContent<Content: View>(
        title: String,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                sectionHeader(title, accentColor: accentColor)
                content()
            }
            .padding(.top, 26)
            .padding(.leading, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String, accentColor: Color) -> some View {
        HStack(spacing: 12) {
            Text(">")
                .foregroundStyle(accentColor)
                .font(SettingsTheme.sectionTitleFont)

            Text(title)
                .font(SettingsTheme.sectionTitleFont)
                .foregroundStyle(SettingsTheme.primaryText)
        }
    }

    private func widgetsSection(accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            widgetTabBar(accentColor: accentColor)

            widgetTabContent(accentColor: accentColor)
        }
    }

    private func widgetTabBar(accentColor: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(WidgetConfigurationTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        selectedWidgetTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(
                            selectedWidgetTab == tab ? accentColor : SettingsTheme.secondaryText
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedWidgetTab == tab ? accentColor.opacity(0.16) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SettingsTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SettingsTheme.border, lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func widgetTabContent(accentColor: Color) -> some View {
        switch selectedWidgetTab {
        case .general:
            generalWidgetSettings(accentColor: accentColor)
        case .music:
            musicWidgetSettings(accentColor: accentColor)
        case .calendar:
            calendarWidgetSettings(accentColor: accentColor)
        case .moon:
            moonWidgetSettings(accentColor: accentColor)
        case .reminders:
            remindersWidgetSettings(accentColor: accentColor)
        case .focusTimer:
            focusTimerWidgetSettings(accentColor: accentColor)
        case .github:
            githubWidgetSettings(accentColor: accentColor)
        case .habits:
            habitsWidgetSettings(accentColor: accentColor)
        case .dayPlans:
            dayPlansWidgetSettings(accentColor: accentColor)
        }
    }

    private func generalWidgetSettings(accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable, disable and reorder widgets.")
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)

                Text("Drag and drop to change their position in the bar.")
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
            }

            enabledWidgetsTray(accentColor: accentColor)

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("AVAILABLE WIDGETS")
                widgetsCard(accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("PAGE SWIPE")
                pageSwipeCard(accentColor: accentColor)
            }
        }
    }

    private func musicWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .nowPlaying,
            description: "Choose the player and compact playback indicator."
        ) {
            SettingsCard {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text("Player")
                            .font(SettingsTheme.rowFont)
                            .foregroundStyle(SettingsTheme.primaryText)

                        Spacer()

                        Picker("", selection: $preferredMusicPlayerRaw) {
                            ForEach(MusicPlayer.allCases) { player in
                                Text(player.title).tag(player.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                        .tint(accentColor)
                        .environment(\.colorScheme, .dark)
                    }
                    .frame(height: 56)

                    SettingsDivider()

                    HStack(spacing: 16) {
                        Text("Bars")
                            .font(SettingsTheme.rowFont)
                            .foregroundStyle(SettingsTheme.primaryText)

                        Spacer()

                        Picker("", selection: $musicVisualizerModeRaw) {
                            ForEach(MusicVisualizerMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                        .tint(accentColor)
                        .environment(\.colorScheme, .dark)
                    }
                    .frame(height: 56)
                }
            }
        }
    }

    private func pageSwipeCard(accentColor: Color) -> some View {
        SettingsCard {
            SettingsToggleRow(
                title: "Invert page swipe direction",
                subtitle: "Swaps which two-finger swipe direction moves to the next page.",
                isOn: $pageSwipeInverted,
                accentColor: accentColor
            )
        }
    }

    private func githubWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .github,
            description: "Show public contribution activity from your GitHub profile."
        ) {
            SettingsCard {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("GitHub username")
                            .font(SettingsTheme.rowFont)

                        Text("Public contributions are shown without authentication.")
                            .font(SettingsTheme.captionFont)
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }

                    Spacer()

                    TextField("username", text: $githubUsername)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(width: 190, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SettingsTheme.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(SettingsTheme.border, lineWidth: 1)
                                )
                        )
                }
                .frame(height: 72)
            }
        }
    }

    private func moonWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .moon,
            description: "Match the Moon's illuminated edge to your local sky."
        ) {
            MoonLocationSettingsCard(
                usesCurrentLocation: $moonUsesCurrentLocation,
                locationName: $moonLocationName,
                accentColor: accentColor
            )
        }
    }

    private func companionWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .companion,
            description: "Care advances only while you are actively using your Mac."
        ) {
            CompanionSettingsCard(accentColor: accentColor)
        }
    }

    private func habitsWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .habits,
            description: "Build daily consistency and review your recent progress."
        ) {
            HabitSettingsContent(service: habits, accentColor: accentColor)
        }
    }

    private func dayPlansWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .dayPlans,
            description: "Configure colored groups for daily tasks. Synced via iCloud Drive when available."
        ) {
            DayPlanSettingsContent(service: dayPlans, accentColor: accentColor)
        }
    }

    private func calendarWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .clock,
            description: "Choose calendars for the widget and configure meeting alerts."
        ) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionLabel("CALENDARS")
                    CalendarListPickerCard(
                        selectedCalendarIdsRaw: $selectedCalendarIdsRaw,
                        accentColor: accentColor,
                        selectionLabel: "Shown in widget and used for alerts"
                    )
                }

                calendarAlertSettings(accentColor: accentColor)
            }
        }
    }

    private func calendarAlertSettings(accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("FULL-SCREEN ALERT")

                SettingsCard {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            title: "Meeting alerts",
                            subtitle: "Cover the screen with a focused reminder when a calendar event is about to begin.",
                            isOn: $calendarAlertsEnabled,
                            accentColor: accentColor
                        )

                        SettingsDivider()

                        CalendarAlertTimingRow(
                            leadMinutes: $calendarAlertLeadMinutes,
                            accentColor: accentColor
                        )

                        SettingsDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Preview")
                                    .font(SettingsTheme.rowFont)
                                    .foregroundStyle(SettingsTheme.primaryText)
                                Text("See how the alert looks without waiting for an event.")
                                    .font(SettingsTheme.descriptionFont)
                                    .foregroundStyle(SettingsTheme.secondaryText)
                            }

                            Spacer()

                            Button("Show preview") {
                                NotificationCenter.default.post(
                                    name: .bangBarPreviewCalendarAlert,
                                    object: nil
                                )
                            }
                            .buttonStyle(SettingsOutlineButtonStyle())
                        }
                        .padding(.vertical, 14)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("BACKGROUND")

                SettingsCard {
                    VStack(spacing: 0) {
                        SettingsStepperRow(
                            title: "Darkness",
                            value: $calendarAlertBackgroundOpacity,
                            range: 0...90,
                            step: 5,
                            unit: "%",
                            resetValue: 62,
                            accentColor: accentColor
                        )

                        SettingsDivider()

                        SettingsStepperRow(
                            title: "Window blur",
                            value: $calendarAlertBlurIntensity,
                            range: BangBarSettings.calendarAlertBlurRadiusRange,
                            step: 4,
                            unit: "px",
                            resetValue: BangBarSettings.defaultCalendarAlertBlurRadius,
                            accentColor: accentColor
                        )
                    }
                }
            }

        }
        .onChange(of: calendarAlertsEnabled) { _, isEnabled in
            guard isEnabled,
                  EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
                return
            }
            EKEventStore().requestFullAccessToEvents { _, _ in }
        }
    }

    private func remindersWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .reminders,
            description: "Choose the reminders list used by the widget."
        ) {
            SettingsCard {
                RemindersListPickerRow(selectedListId: $reminderListId, accentColor: accentColor)
            }
        }
    }

    private func focusTimerWidgetSettings(accentColor: Color) -> some View {
        widgetSpecificSettings(
            widget: .pomodoro,
            description: "Configure focus sessions, breaks and rounds."
        ) {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsStepperRow(
                        title: "Focus duration",
                        value: $pomodoroWorkMinutes,
                        range: 5...90,
                        step: 5,
                        unit: "min",
                        accentColor: accentColor
                    )
                    SettingsDivider()
                    SettingsStepperRow(
                        title: "Short break",
                        value: $pomodoroShortBreakMinutes,
                        range: 1...30,
                        step: 1,
                        unit: "min",
                        accentColor: accentColor
                    )
                    SettingsDivider()
                    SettingsStepperRow(
                        title: "Long break",
                        value: $pomodoroLongBreakMinutes,
                        range: 5...45,
                        step: 5,
                        unit: "min",
                        accentColor: accentColor
                    )
                    SettingsDivider()
                    SettingsStepperRow(
                        title: "Rounds before long break",
                        value: $pomodoroRounds,
                        range: 2...8,
                        step: 1,
                        unit: "",
                        accentColor: accentColor
                    )
                }
            }
        }
    }

    private func widgetSpecificSettings<Content: View>(
        widget: BangBarWidget,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                WidgetIcon(widget: widget, size: 24)
                    .foregroundStyle(SettingsTheme.primaryText)

                VStack(alignment: .leading, spacing: 5) {
                    Text(widget.settingsTitle)
                        .font(SettingsTheme.rowFont)
                        .foregroundStyle(SettingsTheme.primaryText)

                    Text(description)
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                }
            }

            content()
        }
    }

    private func enabledWidgetsTray(accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            enabledWidgetsPageTray(page: 0, accentColor: accentColor)
            enabledWidgetsPageTray(page: 1, accentColor: accentColor)
        }
    }

    private func enabledWidgetsPageTray(page: Int, accentColor: Color) -> some View {
        let enabledWidgets = pageEnabledWidgets(page)

        return VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("PAGE \(page + 1)")

            SettingsCard {
                if enabledWidgets.isEmpty {
                    Text("No widgets on this page")
                        .font(SettingsTheme.captionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 54)
                        .padding(.vertical, 18)
                } else {
                    HStack(spacing: 10) {
                        ForEach(enabledWidgets) { widget in
                            WidgetChip(
                                widget: widget,
                                isActive: draggedWidget == widget,
                                accentColor: accentColor
                            )
                            .frame(maxWidth: .infinity)
                            .animation(.easeInOut(duration: 0.16), value: draggedWidget)
                            .onDrag {
                                draggedWidget = widget
                                return NSItemProvider(object: widget.rawValue as NSString)
                            } preview: {
                                WidgetChip(widget: widget, isDragPreview: true)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: WidgetOrderDropDelegate(
                                    targetWidget: widget,
                                    widgets: $widgetOrder,
                                    draggedWidget: $draggedWidget,
                                    persist: persistWidgetOrder
                                )
                            )
                        }
                    }
                    .padding(.vertical, 18)
                }
            }
        }
    }

    private func widgetsCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(widgetOrder.enumerated()), id: \.element) { index, widget in
                    WidgetSettingsRow(
                        widget: widget,
                        isEnabled: toggleBinding(for: widget),
                        canEnable: canEnableWidget(widget),
                        fitsCurrentPage: widgetFitsCurrentPage(widget),
                        page: pageBinding(for: widget),
                        canAssignToPage: { canAssign(widget, toPage: $0) },
                        accentColor: accentColor
                    )
                    .onDrag {
                        draggedWidget = widget
                        return NSItemProvider(object: widget.rawValue as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: WidgetOrderDropDelegate(
                            targetWidget: widget,
                            widgets: $widgetOrder,
                            draggedWidget: $draggedWidget,
                            persist: persistWidgetOrder
                        )
                    )

                    if index < widgetOrder.count - 1 {
                        SettingsDivider()
                    }
                }
            }
        }
    }

    private func toggleBinding(for widget: BangBarWidget) -> Binding<Bool> {
        switch widget {
        case .nowPlaying:
            return $showNowPlayingWidget
        case .clock:
            return $showClockWidget
        case .moon:
            return $showMoonWidget
        case .pomodoro:
            return $showPomodoroWidget
        case .reminders:
            return $showRemindersWidget
        case .mirror:
            return $showMirrorWidget
        case .system:
            return $showSystemWidget
        case .github:
            return $showGitHubWidget
        case .aiUsage:
            return $showAIUsageWidget
        case .companion:
            return $showCompanionWidget
        case .habits:
            return $showHabitsWidget
        case .translator:
            return $showTranslatorWidget
        case .dayPlans:
            return $showDayPlansWidget
        }
    }

    private func isWidgetEnabled(_ widget: BangBarWidget) -> Bool {
        toggleBinding(for: widget).wrappedValue
    }

    private func widgetPage(for widget: BangBarWidget) -> Int {
        widgetPages[widget.rawValue] ?? 0
    }

    private func pageEnabledWidgets(_ page: Int, excluding excluded: BangBarWidget? = nil) -> [BangBarWidget] {
        widgetOrder.filter { $0 != excluded && isWidgetEnabled($0) && widgetPage(for: $0) == page }
    }

    private func canEnableWidget(_ widget: BangBarWidget) -> Bool {
        if isWidgetEnabled(widget) { return true }

        let proposedWidgets = pageEnabledWidgets(widgetPage(for: widget)) + [widget]
        return PanelLayout.expandedWidth(for: proposedWidgets)
            <= PanelLayout.maximumExpandedWidth(on: NSScreen.main)
    }

    private func canAssign(_ widget: BangBarWidget, toPage targetPage: Int) -> Bool {
        guard isWidgetEnabled(widget) else { return true }

        let proposedWidgets = pageEnabledWidgets(targetPage, excluding: widget) + [widget]
        return PanelLayout.expandedWidth(for: proposedWidgets)
            <= PanelLayout.maximumExpandedWidth(on: NSScreen.main)
    }

    private func widgetFitsCurrentPage(_ widget: BangBarWidget) -> Bool {
        guard isWidgetEnabled(widget) else { return true }

        let maxWidth = PanelLayout.maximumExpandedWidth(on: NSScreen.main)
        return PanelLayout.widgetsThatFit(pageEnabledWidgets(widgetPage(for: widget)), maximumWidth: maxWidth)
            .contains(widget)
    }

    private func pageBinding(for widget: BangBarWidget) -> Binding<Int> {
        Binding(
            get: { widgetPage(for: widget) },
            set: { newPage in
                widgetPages[widget.rawValue] = newPage
                persistWidgetPages()
            }
        )
    }

    private func loadWidgetOrder() {
        widgetOrder = BangBarSettings.widgetOrder(from: widgetOrderRaw)
            .filter { BangBarWidget.visibleCases.contains($0) }
        persistWidgetOrder()
    }

    private func persistWidgetOrder() {
        let normalizedOrder = BangBarSettings.widgetOrderRaw(from: widgetOrder)
        if widgetOrderRaw != normalizedOrder {
            widgetOrderRaw = normalizedOrder
        }
    }

    private func loadWidgetPages() {
        widgetPages = BangBarSettings.widgetPages(from: widgetPagesRaw)
    }

    private func persistWidgetPages() {
        let normalizedPages = BangBarSettings.widgetPagesRaw(from: widgetPages)
        if widgetPagesRaw != normalizedPages {
            widgetPagesRaw = normalizedPages
        }
    }

    private func appearanceCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("Accent color")
                        .font(SettingsTheme.rowFont)

                    Spacer()

                    AccentColorPicker(
                        selection: accentColorBinding,
                        accentColor: accentColor,
                        hexValue: accentColorHex
                    )

                    Button("Reset") {
                        accentColorHex = BangBarSettings.defaultAccentColorHex
                    }
                    .buttonStyle(SettingsOutlineButtonStyle())
                    .disabled(accentColorHex == BangBarSettings.defaultAccentColorHex)
                }
                .frame(height: 52)

                SettingsDivider()
                SettingsToggleRow(title: "Tint walking figure", isOn: $tintWalkingMan, accentColor: accentColor)
            }
        }
    }

    private func clipboardAppearanceCard(accentColor: Color) -> some View {
        SettingsCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Clipboard button position")
                        .font(SettingsTheme.rowFont)
                        .foregroundStyle(SettingsTheme.primaryText)

                    Text("Place the button beside the notch or at the panel's left edge.")
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                }

                Spacer()

                Picker("", selection: $clipboardButtonPositionRaw) {
                    ForEach(ClipboardButtonPosition.allCases) { position in
                        Text(position.title).tag(position.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
                .tint(accentColor)
                .environment(\.colorScheme, .dark)
            }
            .frame(minHeight: 72)
        }
    }

    private func clipboardSettingsCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Storage limit")
                            .font(SettingsTheme.rowFont)
                            .foregroundStyle(SettingsTheme.primaryText)

                        Text("Oldest items are removed automatically when the limit is reached.")
                            .font(SettingsTheme.descriptionFont)
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }

                    Spacer()

                    Picker("", selection: $clipboardStorageLimitMB) {
                        ForEach([50, 100, 250, 500], id: \.self) { limit in
                            Text("\(limit) MB").tag(limit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 112)
                    .tint(accentColor)
                }
                .frame(minHeight: 72)

                SettingsDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Current usage")
                            .font(SettingsTheme.rowFont)
                            .foregroundStyle(SettingsTheme.primaryText)

                        Text("Up to 200 items, with a 20 MB limit per item.")
                            .font(SettingsTheme.descriptionFont)
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }

                    Spacer()

                    Text(clipboardHistory.formattedUsage)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
                .frame(minHeight: 72)

                SettingsDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Clear clipboard history")
                            .font(SettingsTheme.rowFont)
                            .foregroundStyle(SettingsTheme.primaryText)

                        Text("Permanently removes saved text and images.")
                            .font(SettingsTheme.descriptionFont)
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }

                    Spacer()

                    Button("Clear History", action: clipboardHistory.clear)
                        .buttonStyle(SettingsOutlineButtonStyle())
                        .disabled(clipboardHistory.items.isEmpty)
                }
                .frame(minHeight: 72)
            }
        }
    }

    private func clipboardGesturesCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Swipe navigation",
                    subtitle: "Swipe down with two fingers to open Clipboard and up to return to widgets.",
                    isOn: $clipboardSwipeNavigationEnabled,
                    accentColor: accentColor
                )

                if clipboardSwipeNavigationEnabled {
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Invert swipe direction",
                        subtitle: "Swipe up to open Clipboard and down to return to widgets.",
                        isOn: $clipboardSwipeNavigationInverted,
                        accentColor: accentColor
                    )
                }
            }
        }
    }

    private func clipboardTemporaryChangesCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Ignore temporary changes",
                    subtitle: "Skips content when the previous clipboard is restored shortly afterward.",
                    isOn: $clipboardIgnoreTransientChanges,
                    accentColor: accentColor
                )
                if clipboardIgnoreTransientChanges {
                    SettingsDivider()
                    clipboardPickerRow(
                        title: "Wait before saving",
                        subtitle: "One second works well for most transcription apps.",
                        selection: $clipboardTransientDelayMS,
                        values: [500, 1000, 1500, 2000],
                        label: { String(format: "%.1f sec", Double($0) / 1000) },
                        accentColor: accentColor
                    )
                }
            }
        }
    }

    private func clipboardTranscriptionCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Ignore transcription shortcut",
                    subtitle: "Pauses clipboard history while your transcription key is held.",
                    isOn: $clipboardIgnoreShortcutEnabled,
                    accentColor: accentColor
                )
                if clipboardIgnoreShortcutEnabled {
                    SettingsDivider()
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Shortcut")
                                .font(SettingsTheme.rowFont)
                                .foregroundStyle(SettingsTheme.primaryText)
                            Text("Click Record, then press your transcription key. Fn is supported.")
                                .font(SettingsTheme.descriptionFont)
                                .foregroundStyle(SettingsTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 12)
                        ShortcutRecorderField(
                            keyCode: $clipboardIgnoreShortcutKeyCode,
                            modifiers: $clipboardIgnoreShortcutModifiers,
                            label: $clipboardIgnoreShortcutLabel
                        )
                        .frame(width: 142, height: 30)
                    }
                    .padding(.vertical, 14)

                    SettingsDivider()
                    clipboardPickerRow(
                        title: "Protection after release",
                        subtitle: "Allows time for the transcriber to finish pasting and restore the clipboard.",
                        selection: $clipboardIgnoreShortcutGraceMS,
                        values: [500, 1000, 1500, 2000, 3000],
                        label: { String(format: "%.1f sec", Double($0) / 1000) },
                        accentColor: accentColor
                    )
                }
            }
        }
    }

    private func clipboardPickerRow(
        title: String,
        subtitle: String,
        selection: Binding<Int>,
        values: [Int],
        label: @escaping (Int) -> String,
        accentColor: Color
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(SettingsTheme.rowFont).foregroundStyle(SettingsTheme.primaryText)
                Text(subtitle)
                    .font(SettingsTheme.descriptionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Picker("", selection: selection) {
                ForEach(values, id: \.self) { value in Text(label(value)).tag(value) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 112)
            .tint(accentColor)
        }
        .padding(.vertical, 14)
    }
}

private enum WidgetConfigurationTab: CaseIterable, Identifiable {
    case general
    case music
    case calendar
    case moon
    case reminders
    case focusTimer
    case github
    case habits
    case dayPlans

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .moon: return "Moon"
        case .reminders: return "Reminders"
        case .focusTimer: return "Focus Timer"
        case .github: return "GitHub"
        case .habits: return "Habits"
        case .dayPlans: return "Day Plans"
        }
    }
}

private enum SettingsTab: CaseIterable, Identifiable {
    case widgets
    case permissions
    case appearance
    case clipboard
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .widgets:
            return "WIDGETS"
        case .permissions:
            return "PERMISSIONS"
        case .appearance:
            return "APPEARANCE"
        case .clipboard:
            return "CLIPBOARD"
        case .about:
            return "ABOUT"
        }
    }

    var iconAsset: String {
        switch self {
        case .widgets:
            return "sidebarWidgets"
        case .permissions:
            return "sidebarPermissions"
        case .appearance:
            return "sidebarAppearance"
        case .clipboard:
            return "sidebarClipboard"
        case .about:
            return "sidebarAbout"
        }
    }
}

private struct LaunchAtLoginSettingsRow: View {
    let accentColor: Color

    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggleRow(title: "Open BangBar at login", isOn: launchAtLoginBinding, accentColor: accentColor)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(accentColor)
                        .padding(.leading, 2)
                        .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                setLaunchAtLoginEnabled(newValue)
            }
        )
    }

    private func setLaunchAtLoginEnabled(_ shouldEnable: Bool) {
        errorMessage = nil

        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            isEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            errorMessage = error.localizedDescription
        }
    }
}

private struct PrivacySettingsSection: View {
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var automationStatus = "Required to control Spotify and Music"
    @State private var isRequestingAutomation = false
    private let eventStore = EKEventStore()

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                PermissionRow(
                    title: "Camera",
                    status: cameraStatusText,
                    systemImage: "video.fill",
                    buttonTitle: cameraButtonTitle,
                    action: handleCameraAccess
                )

                SettingsDivider()

                PermissionRow(
                    title: "Calendar",
                    status: calendarStatusText,
                    systemImage: "calendar",
                    buttonTitle: calendarButtonTitle,
                    action: handleCalendarAccess
                )

                SettingsDivider()

                PermissionRow(
                    title: "Automation",
                    status: automationStatus,
                    systemImage: "gearshape.2.fill",
                    buttonTitle: isRequestingAutomation ? "Requesting..." : "Request",
                    action: requestAutomationAccess,
                    secondaryButtonTitle: "Open",
                    secondaryAction: {
                        openPrivacySettings(anchor: "Privacy_Automation")
                    },
                    isPrimaryDisabled: isRequestingAutomation
                )
            }
        }
        .onAppear {
            refreshStatuses()
        }
    }

    private var cameraStatusText: String {
        switch cameraStatus {
        case .authorized:
            return "Allowed"
        case .notDetermined:
            return "Not requested"
        case .denied, .restricted:
            return "Permission required in System Settings"
        @unknown default:
            return "Unknown"
        }
    }

    private var calendarStatusText: String {
        switch calendarStatus {
        case .fullAccess, .authorized:
            return "Allowed"
        case .writeOnly:
            return "Write only"
        case .notDetermined:
            return "Not requested"
        case .denied, .restricted:
            return "Permission required in System Settings"
        @unknown default:
            return "Unknown"
        }
    }

    private var cameraButtonTitle: String {
        cameraStatus == .notDetermined ? "Request" : "Open"
    }

    private var calendarButtonTitle: String {
        calendarStatus == .notDetermined || calendarStatus == .writeOnly ? "Request" : "Open"
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
    }

    private func handleCameraAccess() {
        if cameraStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async {
                    refreshStatuses()
                }
            }
        } else {
            openPrivacySettings(anchor: "Privacy_Camera")
        }
    }

    private func handleCalendarAccess() {
        switch calendarStatus {
        case .notDetermined, .writeOnly:
            eventStore.requestFullAccessToEvents { _, _ in
                DispatchQueue.main.async {
                    refreshStatuses()
                }
            }
        default:
            openPrivacySettings(anchor: "Privacy_Calendars")
        }
    }

    private func requestAutomationAccess() {
        guard !isRequestingAutomation else { return }
        isRequestingAutomation = true
        automationStatus = "Waiting for macOS permission prompt..."

        Task { @MainActor in
            let result = await Self.performAutomationProbe()
            isRequestingAutomation = false
            automationStatus = result.message
            if result.shouldOpenSettings {
                openPrivacySettings(anchor: "Privacy_Automation")
            }
        }
    }

    @MainActor
    private static func performAutomationProbe() async -> (message: String, shouldOpenSettings: Bool) {
        let targets = runningMediaPlayers()
        let players = targets.isEmpty ? [("Music", "com.apple.Music")] : targets

        var lastMessage = "Permission was not granted"
        for player in players {
            ensureApplicationIsRunning(bundleID: player.bundleID)
            try? await Task.sleep(for: .milliseconds(500))

            let permissionStatus = automationPermissionStatus(for: player.bundleID)
            if permissionStatus == noErr {
                return verifyAutomationScript(for: player)
            }

            if permissionStatus != errAEEventWouldRequireUserConsent {
                lastMessage = appleEventPermissionMessage(permissionStatus)
                continue
            }

            return verifyAutomationScript(for: player)
        }

        return ("Permission needed: \(lastMessage)", true)
    }

    @MainActor
    private static func runningMediaPlayers() -> [(name: String, bundleID: String)] {
        var players: [(name: String, bundleID: String)] = []
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        if runningBundleIDs.contains("com.apple.Music") {
            players.append(("Music", "com.apple.Music"))
        }
        if runningBundleIDs.contains("com.spotify.client") {
            players.append(("Spotify", "com.spotify.client"))
        }

        return players
    }

    @MainActor
    private static func ensureApplicationIsRunning(bundleID: String) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func automationPermissionStatus(for bundleID: String) -> OSStatus {
        guard let data = bundleID.data(using: .utf8) else { return OSStatus(paramErr) }

        var target = AEAddressDesc()
        let createStatus = data.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                data.count,
                &target
            )
        }
        guard createStatus == noErr else { return OSStatus(createStatus) }
        defer { AEDisposeDesc(&target) }

        return AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEGetData),
            true
        )
    }

    private static func verifyAutomationScript(
        for player: (name: String, bundleID: String)
    ) -> (message: String, shouldOpenSettings: Bool) {
        let script = NSAppleScript(source: """
        tell application "\(player.name)"
            get player state
        end tell
        """)
        var errorInfo: NSDictionary?
        _ = script?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Unknown AppleScript error"
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            return ("Permission needed: \(message) (\(number))", true)
        }

        return ("Allowed for \(player.name)", false)
    }

    private static func appleEventPermissionMessage(_ status: OSStatus) -> String {
        switch status {
        case noErr:
            return "Allowed"
        case OSStatus(errAEEventWouldRequireUserConsent):
            return "macOS needs confirmation"
        case OSStatus(errAEEventNotPermitted):
            return "Automation is denied in System Settings"
        default:
            return "Apple Events error \(status)"
        }
    }

    private func openPrivacySettings(anchor: String) {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let status: String
    let systemImage: String
    let buttonTitle: String
    let action: () -> Void
    var secondaryButtonTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var isPrimaryDisabled = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SettingsTheme.secondaryText)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)

                Text(status)
                    .font(SettingsTheme.descriptionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(buttonTitle, action: action)
                    .buttonStyle(SettingsOutlineButtonStyle())
                    .disabled(isPrimaryDisabled)

                if let secondaryButtonTitle, let secondaryAction {
                    Button(secondaryButtonTitle, action: secondaryAction)
                        .buttonStyle(SettingsOutlineButtonStyle())
                }
            }
        }
        .frame(minHeight: 72)
    }
}

private struct MoonLocationSettingsCard: View {
    @Binding var usesCurrentLocation: Bool
    @Binding var locationName: String
    let accentColor: Color

    @StateObject private var service = MoonLocationService.shared
    @State private var cityQuery = ""

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Current location")
                            .font(SettingsTheme.rowFont)
                        Text(locationStatus)
                            .font(SettingsTheme.captionFont)
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $usesCurrentLocation)
                        .labelsHidden()
                        .tint(accentColor)
                }
                .frame(height: 72)

                SettingsDivider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("City")
                            .font(SettingsTheme.rowFont)
                        Text("Used when automatic location is off. Current: \(locationName)")
                            .font(SettingsTheme.captionFont)
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }

                    Spacer()

                    TextField("City", text: $cityQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(width: 190, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SettingsTheme.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(SettingsTheme.border, lineWidth: 1)
                                )
                        )
                        .disabled(usesCurrentLocation || service.isSearching)
                        .onSubmit { resolveCity() }

                    Button(service.isSearching ? "Searching…" : "Use city") {
                        resolveCity()
                    }
                    .buttonStyle(.bordered)
                    .tint(accentColor)
                    .disabled(usesCurrentLocation || cityQuery.trimmingCharacters(in: .whitespaces).isEmpty || service.isSearching)
                }
                .frame(height: 72)

                if let error = service.searchError {
                    Text(error)
                        .font(SettingsTheme.captionFont)
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            cityQuery = locationName
            if usesCurrentLocation { service.requestCurrentLocation() }
        }
        .onChange(of: usesCurrentLocation) { _, enabled in
            if enabled { service.requestCurrentLocation() }
        }
    }

    private var locationStatus: String {
        switch service.authorizationStatus {
        case .authorizedAlways:
            return "Allowed — using the Mac's location"
        case .notDetermined:
            return "Turn on to request permission"
        case .denied, .restricted:
            return "Permission denied — choose a city below"
        @unknown default:
            return "Location status unavailable"
        }
    }

    private func resolveCity() {
        Task {
            if await service.resolveCity(cityQuery) {
                usesCurrentLocation = false
            }
        }
    }
}

private struct CompanionSettingsCard: View {
    let accentColor: Color
    @StateObject private var service = CompanionService.shared
    @State private var showsResetConfirmation = false

    var body: some View {
        SettingsCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Start over")
                        .font(SettingsTheme.rowFont)
                    Text("Create a new companion and reset all current meters.")
                        .font(SettingsTheme.captionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                }

                Spacer()

                Button("Reset companion") {
                    showsResetConfirmation = true
                }
                .buttonStyle(SettingsOutlineButtonStyle())
            }
            .frame(height: 72)
        }
        .confirmationDialog(
            "Reset your companion?",
            isPresented: $showsResetConfirmation
        ) {
            Button("Reset companion", role: .destructive) { service.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Current progress and meters will be replaced with a new companion.")
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab

    let accentColor: Color

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        accentColor: accentColor
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 14) {
                SettingsIllustration()
                    .frame(height: 190)

                OlchuStudioFooter()
                    .padding(.horizontal, 24)
            }
        }
    }
}

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(tab.iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                Text(tab.title)
                    .font(SettingsTheme.sidebarFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? accentColor : SettingsTheme.secondaryText)
            .padding(.horizontal, 20)
            .frame(width: 208, height: 58)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentColor.opacity(0.18) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? accentColor.opacity(0.75) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsIllustration: View {
    var body: some View {
        Image("settingsIllustration")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct OlchuStudioFooter: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            logo

            Spacer(minLength: 8)

            Text(appVersionLabel)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(SettingsTheme.secondaryText)
                .lineLimit(1)
                .padding(.bottom, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("> OLCHU_")
                .font(.system(size: 8, weight: .light, design: .monospaced))
                .foregroundStyle(SettingsTheme.primaryText)
                .lineLimit(1)

            HStack(alignment: .center, spacing: 3) {
                Text("STUDI")
                    .font(.system(size: 12, weight: .black, design: .default))
                    .foregroundStyle(SettingsTheme.primaryText)
                    .lineLimit(1)
                    .fixedSize()

                logoDot
            }
        }
        .fixedSize()
    }

    private var logoDot: some View {
        Circle()
            .fill(Color(hex: BangBarSettings.defaultAccentColorHex))
            .frame(width: 17, height: 17)
    }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v\(version ?? "0.0")"
    }
}

private struct WidgetChip: View {
    let widget: BangBarWidget
    var isDragPreview = false
    var isActive = false
    var accentColor: Color = SettingsTheme.primaryText

    private var contentColor: Color {
        isActive ? accentColor : SettingsTheme.primaryText
    }

    private var backgroundFill: Color {
        if isDragPreview { return SettingsTheme.background }
        return isActive ? accentColor.opacity(0.16) : SettingsTheme.cardBackground
    }

    private var strokeColor: Color {
        isActive ? accentColor : SettingsTheme.border
    }

    var body: some View {
        HStack(spacing: 8) {
            WidgetIcon(widget: widget, size: 16)

            Text(widget.settingsTitle)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 0)

            dragHandle
        }
        .foregroundStyle(contentColor)
        .padding(.horizontal, 10)
        .frame(width: isDragPreview ? widget.settingsChipWidth : nil, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(strokeColor, lineWidth: isActive ? 1.5 : 1)
                )
        )
    }

    private var dotColor: Color {
        isActive ? accentColor : SettingsTheme.secondaryText.opacity(0.58)
    }

    private var dragHandle: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 4) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 2.5, height: 2.5)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
    }
}

private struct WidgetSettingsRow: View {
    let widget: BangBarWidget
    @Binding var isEnabled: Bool
    let canEnable: Bool
    let fitsCurrentPage: Bool
    @Binding var page: Int
    let canAssignToPage: (Int) -> Bool
    let accentColor: Color

    private var spaceWarning: String? {
        if !canEnable {
            return "Not enough panel space — disable another widget"
        }
        if isEnabled, !fitsCurrentPage {
            return "Not enough room on this page — free up space to show it"
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 18) {
            WidgetIcon(widget: widget, size: 28)
                .foregroundStyle(SettingsTheme.primaryText)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(widget.settingsTitle)
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)

                Text(spaceWarning ?? widget.subtitle)
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(spaceWarning == nil ? SettingsTheme.secondaryText : accentColor.opacity(0.8))
            }

            Spacer()

            if isEnabled {
                Picker("", selection: $page) {
                    Text("Page 1").tag(0).disabled(!canAssignToPage(0))
                    Text("Page 2").tag(1).disabled(!canAssignToPage(1))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 90)
                .tint(accentColor)
            }

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(SettingsSwitchToggleStyle(accentColor: accentColor))
                .disabled(!canEnable)
        }
        .frame(height: 72)
    }
}

private struct WidgetIcon: View {
    let widget: BangBarWidget
    let size: CGFloat

    var body: some View {
        Group {
            if widget == .github {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: size * 0.72, weight: .semibold))
            } else if widget == .aiUsage {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: size * 0.72, weight: .semibold))
            } else if widget == .dayPlans {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: size * 0.72, weight: .semibold))
            } else {
                Image(widget.iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}

private struct WidgetOrderDropDelegate: DropDelegate {
    let targetWidget: BangBarWidget
    @Binding var widgets: [BangBarWidget]
    @Binding var draggedWidget: BangBarWidget?
    let persist: () -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggedWidget,
            draggedWidget != targetWidget,
            let fromIndex = widgets.firstIndex(of: draggedWidget),
            let toIndex = widgets.firstIndex(of: targetWidget)
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            widgets.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
        persist()
    }

    func performDrop(info: DropInfo) -> Bool {
        persist()
        draggedWidget = nil
        return true
    }
}

private extension BangBarWidget {
    var settingsTitle: String {
        switch self {
        case .clock:
            return "Calendar"
        default:
            return title
        }
    }

    var settingsChipWidth: CGFloat {
        let scaledWidth = realPanelWidth * 0.7 + 70
        return max(scaledWidth, minimumReadableChipWidth)
    }

    private var realPanelWidth: CGFloat {
        layoutWidth
    }

    private var minimumReadableChipWidth: CGFloat {
        switch self {
        case .nowPlaying:
            return 160
        case .clock:
            return 170
        case .moon:
            return 150
        case .pomodoro:
            return 174
        case .reminders:
            return 178
        case .mirror:
            return 150
        case .system:
            return 160
        case .github:
            return 160
        case .aiUsage:
            return 190
        case .companion:
            return 176
        case .habits:
            return 190
        case .translator:
            return 190
        case .dayPlans:
            return 190
        }
    }
}

private struct SettingsStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let unit: String
    var resetValue: Int? = nil
    let accentColor: Color

    var body: some View {
        HStack {
            Text(title)
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)

            Spacer()

            HStack(spacing: 0) {
                stepButton(systemName: "minus", enabled: value > range.lowerBound) {
                    value = max(range.lowerBound, value - step)
                }

                Text(valueLabel)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettingsTheme.primaryText)
                    .frame(minWidth: 68)

                stepButton(systemName: "plus", enabled: value < range.upperBound) {
                    value = min(range.upperBound, value + step)
                }
            }
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(SettingsTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SettingsTheme.border, lineWidth: 1)
                    )
            )

            if let resetValue {
                Button("Reset") {
                    value = resetValue
                }
                .buttonStyle(SettingsOutlineButtonStyle())
                .disabled(value == resetValue)
                .padding(.leading, 12)
            }
        }
        .frame(height: 52)
    }

    private var valueLabel: String {
        unit.isEmpty ? "\(value)" : "\(value) \(unit)"
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? accentColor : SettingsTheme.secondaryText.opacity(0.4))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    let accentColor: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SettingsSwitchToggleStyle(accentColor: accentColor))
        }
        .padding(.vertical, subtitle == nil ? 10 : 14)
    }
}

private struct AccentColorPicker: View {
    @Binding var selection: Color
    let accentColor: Color
    let hexValue: String

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor)
                    .frame(width: 66, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )

                Text(hexValue.uppercased())
                    .font(SettingsTheme.labelFont)
                    .foregroundStyle(SettingsTheme.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(SettingsTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SettingsTheme.border, lineWidth: 1)
                    )
            )

            ColorPanelClickOverlay(selection: $selection)
                .frame(width: 210, height: 40)
        }
        .frame(width: 210, height: 40)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ColorPanelClickOverlay: NSViewRepresentable {
    @Binding var selection: Color

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onClick = {
            context.coordinator.openColorPanel()
        }
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        context.coordinator.selection = $selection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class ClickView: NSView {
        var onClick: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Color>

        init(selection: Binding<Color>) {
            self.selection = selection
        }

        func openColorPanel() {
            let panel = NSColorPanel.shared
            let color = NSColor(selection.wrappedValue).usingColorSpace(.sRGB) ?? NSColor(selection.wrappedValue)
            panel.showsAlpha = false
            panel.color = color
            panel.setTarget(self)
            panel.setAction(#selector(colorChanged(_:)))
            panel.makeKeyAndOrderFront(nil)
        }

        @objc func colorChanged(_ sender: NSColorPanel) {
            let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
            selection.wrappedValue = Color(nsColor: color)
        }
    }
}

private struct SettingsSwitchToggleStyle: ToggleStyle {
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? accentColor : Color.white.opacity(0.07))
                    .overlay(
                        Capsule()
                            .stroke(
                                configuration.isOn ? accentColor.opacity(0.95) : Color.white.opacity(0.28),
                                lineWidth: 1.2
                            )
                    )

                Circle()
                    .fill(SettingsTheme.primaryText)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
            .frame(width: 54, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(SettingsTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SettingsTheme.border, lineWidth: 1)
                    )
            )
    }
}

struct SettingsSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(SettingsTheme.labelFont)
            .foregroundStyle(SettingsTheme.secondaryText)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsTheme.border)
            .frame(height: 1)
    }
}

private struct DottedDivider: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<120, id: \.self) { _ in
                Circle()
                    .fill(SettingsTheme.secondaryText.opacity(0.5))
                    .frame(width: 1.5, height: 1.5)
            }
        }
        .frame(width: 1)
    }
}

private struct SettingsOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(configuration.isPressed ? SettingsTheme.primaryText.opacity(0.7) : SettingsTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? SettingsTheme.border.opacity(0.45) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(SettingsTheme.border, lineWidth: 1)
                    )
            )
    }
}

private struct RemindersListPickerRow: View {
    @Binding var selectedListId: String
    let accentColor: Color

    @State private var lists: [(id: String, title: String)] = []

    var body: some View {
        HStack {
            Text("List")
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)

            Spacer()

            Menu {
                Button("All Reminders") { selectedListId = "" }
                if !lists.isEmpty {
                    Divider()
                    ForEach(lists, id: \.id) { list in
                        Button(list.title) { selectedListId = list.id }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedTitle)
                        .font(SettingsTheme.captionFont)
                        .foregroundStyle(SettingsTheme.primaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SettingsTheme.border.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(SettingsTheme.border, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .environment(\.colorScheme, .dark)
            .fixedSize()
        }
        .frame(height: 52)
        .onAppear { loadLists() }
    }

    private var selectedTitle: String {
        if selectedListId.isEmpty { return "All Reminders" }
        return lists.first { $0.id == selectedListId }?.title ?? "All Reminders"
    }

    private func loadLists() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else { return }
        let store = EKEventStore()
        lists = store.calendars(for: .reminder).map { (id: $0.calendarIdentifier, title: $0.title) }
    }
}

private struct CalendarAlertTimingRow: View {
    @Binding var leadMinutes: Int
    let accentColor: Color

    private let options = [0, 1, 5, 10, 15]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Show alert")
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)

                Text("Choose how early the full-screen reminder appears.")
                    .font(SettingsTheme.descriptionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
            }

            Spacer()

            Menu {
                ForEach(options, id: \.self) { minutes in
                    Button(label(for: minutes)) {
                        leadMinutes = minutes
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(label(for: leadMinutes))
                        .font(SettingsTheme.captionFont)
                        .foregroundStyle(SettingsTheme.primaryText)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SettingsTheme.border.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(SettingsTheme.border, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 14)
    }

    private func label(for minutes: Int) -> String {
        minutes == 0 ? "At start time" : "\(minutes) min before"
    }
}

private struct CalendarListPickerCard: View {
    @Binding var selectedCalendarIdsRaw: String
    let accentColor: Color
    let selectionLabel: String

    @State private var calendars: [(id: String, title: String, color: NSColor)] = []
    @State private var authorizationStatus = EKEventStore.authorizationStatus(for: .event)

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                if isAuthorized {
                    if calendars.isEmpty {
                        CalendarPickerStatusRow(text: "No calendars available")
                    } else {
                        calendarActionsRow
                        SettingsDivider()

                        ForEach(Array(calendars.enumerated()), id: \.element.id) { index, calendar in
                            calendarRow(calendar)

                            if index < calendars.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                } else {
                    CalendarPickerStatusRow(text: "Allow Calendar access to choose calendars")
                }
            }
        }
        .onAppear { loadCalendars() }
    }

    private var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    private var selectedCalendarIds: [String]? {
        BangBarSettings.selectedCalendarIds(from: selectedCalendarIdsRaw)
    }

    private var calendarActionsRow: some View {
        HStack(spacing: 10) {
            Text(selectionLabel)
                .font(SettingsTheme.captionFont)
                .foregroundStyle(SettingsTheme.secondaryText)

            Spacer()

            Button("All", action: selectAll)
                .buttonStyle(SettingsOutlineButtonStyle())

            Button("None", action: clearAll)
                .buttonStyle(SettingsOutlineButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private func isSelected(_ id: String) -> Bool {
        selectedCalendarIds?.contains(id) ?? true
    }

    private func calendarRow(_ calendar: (id: String, title: String, color: NSColor)) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(nsColor: calendar.color))
                .frame(width: 10, height: 10)

            Text(calendar.title)
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 16)

            Toggle("", isOn: binding(for: calendar.id))
                .labelsHidden()
                .toggleStyle(SettingsSwitchToggleStyle(accentColor: accentColor))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { isSelected(id) },
            set: { isSelected in
                updateSelection(id: id, isSelected: isSelected)
            }
        )
    }

    private func updateSelection(id: String, isSelected: Bool) {
        var selectedIds = Set(selectedCalendarIds ?? calendars.map(\.id))

        if isSelected {
            selectedIds.insert(id)
        } else {
            selectedIds.remove(id)
        }

        let orderedIds = calendars
            .map(\.id)
            .filter { selectedIds.contains($0) }

        selectedCalendarIdsRaw = orderedIds.count == calendars.count
            ? ""
            : BangBarSettings.selectedCalendarIdsRaw(from: orderedIds)
    }

    private func selectAll() {
        selectedCalendarIdsRaw = ""
    }

    private func clearAll() {
        selectedCalendarIdsRaw = BangBarSettings.selectedCalendarIdsRaw(from: [])
    }

    private func loadCalendars() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized else {
            calendars = []
            return
        }

        let store = EKEventStore()
        calendars = store.calendars(for: .event)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { calendar in
                (
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    color: NSColor(cgColor: calendar.cgColor) ?? .white
                )
            }
    }
}

private struct CalendarPickerStatusRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsTheme.captionFont)
            .foregroundStyle(SettingsTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 18)
    }
}

enum SettingsTheme {
    static let background = Color.black
    static let cardBackground = Color.black.opacity(0.35)
    static let border = Color.white.opacity(0.13)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.52)

    static let titleFont = Font.system(size: 18, weight: .medium, design: .monospaced)
    static let sectionTitleFont = Font.system(size: 20, weight: .medium, design: .monospaced)
    static let sidebarFont = Font.system(size: 17, weight: .semibold, design: .monospaced)
    static let labelFont = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let chipFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let rowFont = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let descriptionFont = Font.system(size: 12, weight: .regular, design: .monospaced)
}
