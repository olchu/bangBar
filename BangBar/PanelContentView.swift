import SwiftUI
import Combine

struct PanelContentView: View {
    @ObservedObject var state: PanelState
    // Not observed: the root reads none of their values, and their ticks would re-render the whole panel.
    let nowPlaying: NowPlayingService
    let pomodoro: PomodoroService
    let clipboardHistory: ClipboardHistoryService
    let onOpenSettings: () -> Void

    @AppStorage(BangBarSettings.Key.showNowPlayingWidget) private var showNowPlayingWidget = true
    @AppStorage(BangBarSettings.Key.showClockWidget) private var showClockWidget = true
    @AppStorage(BangBarSettings.Key.showMoonWidget) private var showMoonWidget = true
    @AppStorage(BangBarSettings.Key.showMirrorWidget) private var showMirrorWidget = true
    @AppStorage(BangBarSettings.Key.showSystemWidget) private var showSystemWidget = false
    @AppStorage(BangBarSettings.Key.showGitHubWidget) private var showGitHubWidget = false
    @AppStorage(BangBarSettings.Key.showAIUsageWidget) private var showAIUsageWidget = false
    @AppStorage(BangBarSettings.Key.showHabitsWidget) private var showHabitsWidget = false
    @AppStorage(BangBarSettings.Key.showTranslatorWidget) private var showTranslatorWidget = false
    @AppStorage(BangBarSettings.Key.showDayPlansWidget) private var showDayPlansWidget = false
    @AppStorage(BangBarSettings.Key.showPomodoroWidget) private var showPomodoroWidget = true
    @AppStorage(BangBarSettings.Key.showCountdownWidget) private var showCountdownWidget = false
    @AppStorage(BangBarSettings.Key.showRemindersWidget) private var showRemindersWidget = true
    @AppStorage(BangBarSettings.Key.widgetOrder) private var widgetOrderRaw = BangBarSettings.defaultWidgetOrderRaw
    @AppStorage(BangBarSettings.Key.widgetPages) private var widgetPagesRaw = "{}"
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @StateObject private var mirror = MirrorCameraService()
    @StateObject private var calendarEvents = CalendarEventService()
    @StateObject private var reminders = ReminderService()
    @StateObject private var githubContributions = GitHubContributionsService()
    @StateObject private var aiUsage = AIUsageService()
    @StateObject private var habits = HabitService.shared
    @StateObject private var countdown = CountdownService.shared
    @StateObject private var dayPlans = DayPlanService.shared
    // @State, not @StateObject: only the widgets that show the time observe it, so its ticks skip the root body.
    @State private var panelClock = PanelClock()
    private let panelBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)

    var body: some View {
        let pages = activeWidgetPages()
        let timeUpdateInterval = timeUpdateInterval(for: pages[state.currentPage])
        GeometryReader { geo in
            let hideExpandedArtwork = if let heroProgress = state.artworkHeroProgress {
                heroProgress < 0.995
            } else {
                false
            }

            ZStack {
                panelBlack
                    .ignoresSafeArea()

                if state.isCompact {
                    compactWidget
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ZStack {
                        pagedWidgets(pages, hideExpandedArtwork: hideExpandedArtwork)
                            .frame(width: geo.size.width, alignment: .topLeading)
                            .opacity(state.showsClipboardHistory ? 0 : 1)
                            .allowsHitTesting(!state.showsClipboardHistory)
                            .accessibilityHidden(state.showsClipboardHistory)

                        if state.showsClipboardHistory {
                            ClipboardHistoryView(
                                service: clipboardHistory,
                                filter: state.clipboardFilter,
                                topSafeInset: state.topSafeInset,
                                isPresented: true
                            )
                            .transition(.opacity)
                        }
                    }
                    .opacity(state.contentVisible ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.10), value: state.contentVisible)
                    .animation(.easeOut(duration: 0.16), value: state.showsClipboardHistory)
                }

                if !state.isCompact, !state.showsClipboardHistory, !pages[1].isEmpty {
                    // Centered in the bottom edge padding, so a widget filled to its full height never touches it.
                    pageIndicator
                        .position(x: geo.size.width / 2, y: geo.size.height - PanelLayout.expandedVisibleEdgePadding / 2)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                        .opacity(state.contentVisible ? 1.0 : 0.0)
                        .allowsHitTesting(false)
                }

                if let progress = state.artworkHeroProgress {
                    ArtworkHeroView(
                        service: nowPlaying,
                        progress: progress,
                        panelSize: geo.size
                    )
                    .allowsHitTesting(false)
                    .zIndex(10)
                }

                if state.isExpanded {
                    PanelTopBar(
                        showsClipboardHistory: $state.showsClipboardHistory,
                        clipboardFilter: $state.clipboardFilter,
                        width: geo.size.width,
                        height: state.topSafeInset,
                        clipboardHistory: clipboardHistory,
                        onOpenSettings: onOpenSettings
                    )
                    .opacity(state.contentVisible ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.10), value: state.contentVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(20)
                }
            }
        }
        .clipShape(NotchPanelShape())
        .scaleEffect(panelScale, anchor: .top)
        .opacity(state.isExpanded || state.isCompact ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.66), value: state.isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.isCompact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: timeUpdateInterval, initial: true) { _, interval in
            panelClock.setUpdateInterval(interval)
            if interval == 1 {
                calendarEvents.start()
                calendarEvents.refreshIfNeeded(now: panelClock.date)
            }
        }
        .onAppear {
            TooltipManager.shared.setPresentationEnabled(!state.showsClipboardHistory)
            if showDayPlansWidget { dayPlans.reload() }
        }
        .onChange(of: state.showsClipboardHistory) { _, isPresented in
            TooltipManager.shared.setPresentationEnabled(!isPresented)
            if !isPresented {
                clipboardHistory.releaseCachedImages()
            }
        }
        .onChange(of: state.isExpanded) { _, isExpanded in
            if !isExpanded {
                mirror.stop()
            } else {
                if showDayPlansWidget { dayPlans.reload() }
            }
        }
        .onChange(of: state.isCompact) { _, isCompact in
            if isCompact {
                mirror.stop()
            }
        }
        .onChange(of: showDayPlansWidget) { _, isVisible in
            if isVisible { dayPlans.reload() }
        }
        .onChange(of: showMirrorWidget) { _, isVisible in
            if !isVisible {
                mirror.stop()
            }
        }
        .onDisappear {
            panelClock.stop()
            reminders.stop()
            mirror.stop()
        }
    }

    private var panelScale: CGFloat {
        if state.isExpanded { return 0.955 }
        if state.isCompact { return 1.0 }
        return 0.22
    }

    private func timeUpdateInterval(for visibleWidgets: [BangBarWidget]) -> TimeInterval? {
        guard state.isExpanded,
              state.contentVisible,
              !state.showsClipboardHistory else {
            return nil
        }

        if visibleWidgets.contains(.clock) { return 1 }
        if visibleWidgets.contains(.moon) || visibleWidgets.contains(.countdown) { return 60 }
        return nil
    }

    @ViewBuilder
    private var compactWidget: some View {
        switch state.compactContent {
        case .clipboardGroup:
            CompactClipboardGroupWidget(service: clipboardHistory)
        case .pomodoro:
            CompactPomodoroWidget(service: pomodoro)
        case .nowPlaying:
            CompactNowPlayingWidget(
                service: nowPlaying,
                artworkRevealAllowed: state.compactArtworkRevealAllowed,
                indicatorRevealAllowed: state.compactIndicatorRevealAllowed,
                animateArtworkReveal: state.compactArtworkRevealAnimated,
                hideArtwork: state.artworkHeroProgress != nil
            )
        }
    }

    @ViewBuilder
    private func pagedWidgets(_ pages: [[BangBarWidget]], hideExpandedArtwork: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            let currentPageWidth = PanelLayout.expandedWidth(for: pages[state.currentPage])
            pageLayer(page: 0, widgets: pages[0], currentPageWidth: currentPageWidth, hideExpandedArtwork: hideExpandedArtwork)

            if !pages[1].isEmpty {
                pageLayer(page: 1, widgets: pages[1], currentPageWidth: currentPageWidth, hideExpandedArtwork: hideExpandedArtwork)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.currentPage)
    }

    @ViewBuilder
    private func pageLayer(page: Int, widgets: [BangBarWidget], currentPageWidth: CGFloat, hideExpandedArtwork: Bool) -> some View {
        let isActive = state.isExpanded
            && state.contentVisible
            && !state.showsClipboardHistory
            && state.currentPage == page
        widgetRow(
            for: widgets,
            hideExpandedArtwork: hideExpandedArtwork,
            isActive: isActive
        )
            .offset(x: pageLayerOffset(page: page, widgets: widgets, currentPageWidth: currentPageWidth))
    }

    private func pageLayerOffset(page: Int, widgets: [BangBarWidget], currentPageWidth: CGFloat) -> CGFloat {
        if page == state.currentPage {
            return 0
        } else if page > state.currentPage {
            // Appears to the right: must clear the currently visible page's own width,
            // regardless of how narrow this (still off-screen) page itself is.
            return currentPageWidth
        } else {
            // Appears to the left: must clear its own width, since it extends
            // rightward from its offset origin toward x = 0.
            return -PanelLayout.expandedWidth(for: widgets)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { page in
                Circle()
                    .fill(page == state.currentPage ? Color(hex: accentColorHex) : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
    }

    @ViewBuilder
    private func widgetRow(
        for widgets: [BangBarWidget],
        hideExpandedArtwork: Bool,
        isActive: Bool
    ) -> some View {
        Group {
            if widgets.isEmpty {
                EmptyWidgetsView()
                    .frame(
                        width: PanelLayout.emptyWidgetWidth,
                        height: PanelLayout.nowPlayingWidgetHeight,
                        alignment: .center
                    )
            } else {
                HStack(spacing: PanelLayout.expandedWidgetSpacing) {
                    widgetContent(
                        for: widgets,
                        hideExpandedArtwork: hideExpandedArtwork,
                        isActive: isActive
                    )
                }
            }
        }
        .padding(.horizontal, PanelLayout.expandedHorizontalPadding)
        .padding(.top, state.topSafeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func widgetContent(
        for widgets: [BangBarWidget],
        hideExpandedArtwork: Bool,
        isActive: Bool
    ) -> some View {
        Group {
            ForEach(Array(widgets.enumerated()), id: \.element) { index, widget in
                if index > 0 {
                    Divider()
                        .background(Color.white.opacity(0.2))
                        .frame(
                            width: PanelLayout.expandedDividerWidth,
                            height: PanelLayout.expandedDividerHeight
                        )
                }

                switch widget {
                case .nowPlaying:
                    Group {
                        if state.contentVisible {
                            NowPlayingWidget(
                                service: nowPlaying,
                                hideArtwork: hideExpandedArtwork,
                                isActive: isActive
                            )
                        } else {
                            EmptyView()
                        }
                    }
                    .frame(
                        width: PanelLayout.nowPlayingWidgetWidth,
                        height: PanelLayout.nowPlayingWidgetHeight,
                        alignment: .topLeading
                    )
                case .clock:
                    PanelClockReader(clock: panelClock) { date in
                        ClockWidget(
                            date: date,
                            calendarEvents: calendarEvents,
                            isPanelContentVisible: isActive
                        )
                        .onChange(of: date) { _, date in
                            // The clock also ticks (every 60 s) for Moon/Countdown while this page is off-screen.
                            if isActive {
                                calendarEvents.refreshIfNeeded(now: date)
                            }
                        }
                    }
                        .frame(width: PanelLayout.clockWidgetWidth, alignment: .leading)
                case .moon:
                    PanelClockReader(clock: panelClock) { MoonWidget(date: $0) }
                        .frame(
                            width: PanelLayout.moonWidgetWidth,
                            height: PanelLayout.nowPlayingWidgetHeight,
                            alignment: .center
                        )
                case .pomodoro:
                    PomodoroWidget(service: pomodoro)
                case .countdown:
                    PanelClockReader(clock: panelClock) { CountdownWidget(service: countdown, date: $0) }
                case .reminders:
                    RemindersWidget(
                        service: reminders,
                        isPanelContentVisible: isActive
                    )
                        .frame(
                            width: PanelLayout.remindersWidgetWidth,
                            height: PanelLayout.nowPlayingWidgetHeight,
                            alignment: .topLeading
                        )
                case .mirror:
                    MirrorWidget(service: mirror, isActive: isActive)
                        .frame(
                            width: PanelLayout.mirrorWidgetWidth,
                            height: PanelLayout.mirrorWidgetHeight
                        )
                case .system:
                    SystemWidget(isActive: isActive)
                case .github:
                    GitHubWidget(contributions: githubContributions, isActive: isActive)
                case .aiUsage:
                    AIUsageWidget(service: aiUsage, isActive: isActive)
                case .companion:
                    EmptyView()
                case .habits:
                    HabitsWidget(
                        service: habits,
                        isPanelContentVisible: isActive
                    )
                case .translator:
                    TranslatorWidget(isPanelExpanded: state.isExpanded)
                case .dayPlans:
                    DayPlansWidget(
                        service: dayPlans,
                        isPanelContentVisible: isActive
                    )
                }
            }
        }
    }

    private func activeWidgetPages() -> [[BangBarWidget]] {
        let pageAssignments = BangBarSettings.widgetPages(from: widgetPagesRaw)
        let enabledWidgets = BangBarSettings.widgetOrder(from: widgetOrderRaw).filter(isWidgetVisible)
        let maximumWidth = PanelLayout.maximumExpandedWidth(on: NSScreen.main)
        return [0, 1].map { page in
            PanelLayout.widgetsThatFit(
                enabledWidgets.filter { (pageAssignments[$0.rawValue] ?? 0) == page },
                maximumWidth: maximumWidth
            )
        }
    }

    private func isWidgetVisible(_ widget: BangBarWidget) -> Bool {
        switch widget {
        case .nowPlaying:
            return showNowPlayingWidget
        case .clock:
            return showClockWidget
        case .moon:
            return showMoonWidget
        case .pomodoro:
            return showPomodoroWidget
        case .countdown:
            return showCountdownWidget
        case .reminders:
            return showRemindersWidget
        case .mirror:
            return showMirrorWidget
        case .system:
            return showSystemWidget
        case .github:
            return showGitHubWidget
        case .aiUsage:
            return showAIUsageWidget
        case .companion:
            return false
        case .habits:
            return showHabitsWidget
        case .translator:
            return showTranslatorWidget
        case .dayPlans:
            return showDayPlansWidget
        }
    }
}

private struct PanelClockReader<Content: View>: View {
    @ObservedObject var clock: PanelClock
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        content(clock.date)
    }
}

@MainActor
private final class PanelClock: ObservableObject {
    @Published private(set) var date = Date()

    private var timer: Timer?
    private var updateInterval: TimeInterval?

    deinit {
        timer?.invalidate()
    }

    func setUpdateInterval(_ interval: TimeInterval?) {
        guard interval != updateInterval else { return }
        stop()
        guard let interval else { return }

        updateInterval = interval
        date = Date()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.date = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        updateInterval = nil
    }
}

private struct EmptyWidgetsView: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            Text("Widgets are disabled")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
