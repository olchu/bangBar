import SwiftUI
import Combine

struct PanelContentView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var pomodoro: PomodoroService
    let onOpenSettings: () -> Void

    @AppStorage(BangBarSettings.Key.showNowPlayingWidget) private var showNowPlayingWidget = true
    @AppStorage(BangBarSettings.Key.showClockWidget) private var showClockWidget = true
    @AppStorage(BangBarSettings.Key.showMoonWidget) private var showMoonWidget = true
    @AppStorage(BangBarSettings.Key.showMirrorWidget) private var showMirrorWidget = true
    @AppStorage(BangBarSettings.Key.showPomodoroWidget) private var showPomodoroWidget = true
    @AppStorage(BangBarSettings.Key.showRemindersWidget) private var showRemindersWidget = true
    @AppStorage(BangBarSettings.Key.widgetOrder) private var widgetOrderRaw = BangBarSettings.defaultWidgetOrderRaw
    @StateObject private var mirror = MirrorCameraService()
    @StateObject private var calendarEvents = CalendarEventService()
    @StateObject private var reminders = ReminderService()
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
                    HStack(spacing: PanelLayout.expandedWidgetSpacing) {
                        expandedWidgets(hideExpandedArtwork: hideExpandedArtwork)
                    }
                    .padding(.horizontal, PanelLayout.expandedHorizontalPadding)
                    .padding(.bottom, PanelLayout.expandedVisibleEdgePadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .opacity(state.contentVisible ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.18), value: state.contentVisible)
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
                    PanelChromeControls(
                        onOpenSettings: onOpenSettings
                    )
                    .padding(.top, 0)
                    .padding(.trailing, 52)
                    .opacity(state.contentVisible ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.16), value: state.contentVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(20)
                }
            }
        }
        .clipShape(NotchPanelShape())
        .scaleEffect(panelScale, anchor: .top)
        .opacity(state.isExpanded || state.isCompact ? 1.0 : 0.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.66), value: state.isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.isCompact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(timer) { date in
            currentTime = date
            calendarEvents.refreshIfNeeded(now: date)
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
    private func expandedWidgets(hideExpandedArtwork: Bool) -> some View {
        let widgets = activeWidgets

        if widgets.isEmpty {
            EmptyWidgetsView()
                .frame(
                    width: PanelLayout.emptyWidgetWidth,
                    height: PanelLayout.nowPlayingWidgetHeight,
                    alignment: .center
                )
        } else {
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
                        .offset(x: -8)
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
                    RemindersWidget(service: reminders)
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
                }
            }
        }
    }

    private var activeWidgets: [BangBarWidget] {
        BangBarSettings.widgetOrder(from: widgetOrderRaw).filter(isWidgetVisible)
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
        }
    }
}

private struct PanelChromeControls: View {
    let onOpenSettings: () -> Void

    var body: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .help("Настройки")
        .buttonStyle(PanelChromeButtonStyle())
    }
}

private struct PanelChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.42 : 0.56))
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EmptyWidgetsView: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            Text("Виджеты выключены")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
