import SwiftUI
import Combine

struct PanelContentView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var pomodoro: PomodoroService
    @ObservedObject var clipboardHistory: ClipboardHistoryService
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
    @AppStorage(BangBarSettings.Key.showPomodoroWidget) private var showPomodoroWidget = true
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
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let panelBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)

    var body: some View {
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
                        pagedWidgets(hideExpandedArtwork: hideExpandedArtwork)
                            .opacity(state.showsClipboardHistory ? 0 : 1)
                            .allowsHitTesting(!state.showsClipboardHistory)
                            .accessibilityHidden(state.showsClipboardHistory)

                        ClipboardHistoryView(
                            service: clipboardHistory,
                            filter: state.clipboardFilter,
                            topSafeInset: state.topSafeInset
                        )
                        .opacity(state.showsClipboardHistory ? 1 : 0)
                        .allowsHitTesting(state.showsClipboardHistory)
                        .accessibilityHidden(!state.showsClipboardHistory)
                    }
                    .opacity(state.contentVisible ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.10), value: state.contentVisible)
                    .animation(.easeOut(duration: 0.16), value: state.showsClipboardHistory)
                }

                if !state.isCompact, !state.showsClipboardHistory, !activeWidgets(forPage: 1).isEmpty {
                    pageIndicator
                        .position(x: geo.size.width / 2, y: geo.size.height - 16)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                        .opacity(state.contentVisible ? 1.0 : 0.0)
                        .allowsHitTesting(false)
                }

                if let progress = state.artworkHeroProgress, nowPlaying.isAvailable {
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
                        height: state.topSafeInset,
                        isClearDisabled: clipboardHistory.items.isEmpty,
                        activeGroupName: clipboardHistory.activeGroup?.name,
                        activeGroupItemCount: clipboardHistory.activeGroupItemCount,
                        onNewGroup: {
                            state.clipboardFilter = .images
                            clipboardHistory.startNewGroup()
                        },
                        onStopGroup: clipboardHistory.stopCollecting,
                        onClear: clipboardHistory.clear,
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
        .onReceive(timer) { date in
            currentTime = date
            calendarEvents.refreshIfNeeded(now: date)
            habits.refreshDay(now: date)
        }
        .onAppear {
            if showClockWidget { calendarEvents.start() }
            if showRemindersWidget { reminders.start() }
        }
        .onChange(of: state.isExpanded) { _, isExpanded in
            if !isExpanded {
                mirror.stop()
            } else {
                if showClockWidget { calendarEvents.start() }
                if showRemindersWidget { reminders.refresh() }
            }
        }
        .onChange(of: state.isCompact) { _, isCompact in
            if isCompact {
                mirror.stop()
            }
        }
        .onChange(of: showClockWidget) { _, isVisible in
            if isVisible { calendarEvents.start() }
        }
        .onChange(of: showRemindersWidget) { _, isVisible in
            if isVisible { reminders.start() }
        }
        .onChange(of: showMirrorWidget) { _, isVisible in
            if !isVisible {
                mirror.stop()
            }
        }
    }

    private var panelScale: CGFloat {
        if state.isExpanded { return 0.955 }
        if state.isCompact { return 1.0 }
        return 0.22
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
    private func pagedWidgets(hideExpandedArtwork: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            pageLayer(page: 0, hideExpandedArtwork: hideExpandedArtwork)

            if !activeWidgets(forPage: 1).isEmpty {
                pageLayer(page: 1, hideExpandedArtwork: hideExpandedArtwork)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.currentPage)
    }

    @ViewBuilder
    private func pageLayer(page: Int, hideExpandedArtwork: Bool) -> some View {
        let widgets = activeWidgets(forPage: page)
        widgetRow(for: widgets, hideExpandedArtwork: hideExpandedArtwork)
            .offset(x: pageLayerOffset(page: page, widgets: widgets))
    }

    private func pageLayerOffset(page: Int, widgets: [BangBarWidget]) -> CGFloat {
        if page == state.currentPage {
            return 0
        } else if page > state.currentPage {
            // Appears to the right: must clear the currently visible page's own width,
            // regardless of how narrow this (still off-screen) page itself is.
            return PanelLayout.expandedWidth(for: activeWidgets(forPage: state.currentPage))
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
    private func widgetRow(for widgets: [BangBarWidget], hideExpandedArtwork: Bool) -> some View {
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
                    widgetContent(for: widgets, hideExpandedArtwork: hideExpandedArtwork)
                }
            }
        }
        .padding(.horizontal, PanelLayout.expandedHorizontalPadding)
        .padding(.top, state.topSafeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func widgetContent(for widgets: [BangBarWidget], hideExpandedArtwork: Bool) -> some View {
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
                    NowPlayingWidget(
                        service: nowPlaying,
                        hideArtwork: hideExpandedArtwork
                    )
                    .frame(
                        width: PanelLayout.nowPlayingWidgetWidth,
                        height: PanelLayout.nowPlayingWidgetHeight,
                        alignment: .topLeading
                    )
                case .clock:
                    ClockWidget(date: currentTime, calendarEvents: calendarEvents)
                        .frame(width: PanelLayout.clockWidgetWidth, alignment: .leading)
                case .moon:
                    MoonWidget(date: currentTime)
                        .frame(
                            width: PanelLayout.moonWidgetWidth,
                            height: PanelLayout.nowPlayingWidgetHeight,
                            alignment: .center
                        )
                case .pomodoro:
                    PomodoroWidget(service: pomodoro)
                case .reminders:
                    RemindersWidget(
                        service: reminders,
                        isPanelContentVisible: state.contentVisible && !state.showsClipboardHistory
                    )
                        .frame(
                            width: PanelLayout.remindersWidgetWidth,
                            height: PanelLayout.nowPlayingWidgetHeight,
                            alignment: .topLeading
                        )
                case .mirror:
                    MirrorWidget(service: mirror)
                        .frame(
                            width: PanelLayout.mirrorWidgetWidth,
                            height: PanelLayout.mirrorWidgetHeight
                        )
                case .system:
                    SystemWidget()
                case .github:
                    GitHubWidget(contributions: githubContributions)
                case .aiUsage:
                    AIUsageWidget(service: aiUsage)
                case .companion:
                    EmptyView()
                case .habits:
                    HabitsWidget(
                        service: habits,
                        isPanelContentVisible: state.contentVisible && !state.showsClipboardHistory
                    )
                case .translator:
                    TranslatorWidget(isPanelExpanded: state.isExpanded)
                }
            }
        }
    }

    private func activeWidgets(forPage page: Int) -> [BangBarWidget] {
        let pageAssignments = BangBarSettings.widgetPages(from: widgetPagesRaw)
        let enabledWidgets = BangBarSettings.widgetOrder(from: widgetOrderRaw)
            .filter(isWidgetVisible)
            .filter { (pageAssignments[$0.rawValue] ?? 0) == page }
        return PanelLayout.widgetsThatFit(
            enabledWidgets,
            maximumWidth: PanelLayout.maximumExpandedWidth(on: NSScreen.main)
        )
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
        }
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
