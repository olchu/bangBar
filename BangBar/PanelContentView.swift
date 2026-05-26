import SwiftUI
import Combine

struct PanelContentView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var nowPlaying: NowPlayingService
    let onOpenSettings: () -> Void

    @AppStorage(BangBarSettings.Key.showNowPlayingWidget) private var showNowPlayingWidget = true
    @AppStorage(BangBarSettings.Key.showClockWidget) private var showClockWidget = true
    @AppStorage(BangBarSettings.Key.showMirrorWidget) private var showMirrorWidget = true
    @AppStorage(BangBarSettings.Key.showPomodoroWidget) private var showPomodoroWidget = true
    @StateObject private var mirror = MirrorCameraService()
    @StateObject private var calendarEvents = CalendarEventService()
    @StateObject private var pomodoro = PomodoroService()
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
                    CompactNowPlayingWidget(
                        service: nowPlaying,
                        artworkRevealAllowed: state.compactArtworkRevealAllowed,
                        indicatorRevealAllowed: state.compactIndicatorRevealAllowed,
                        animateArtworkReveal: state.compactArtworkRevealAnimated,
                        hideArtwork: state.artworkHeroProgress != nil
                    )
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
                    .padding(.top, 10)
                    .padding(.trailing, 52)
                    .opacity(state.contentVisible ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.16), value: state.contentVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(20)
                }
            }
        }
        .clipShape(NotchPanelShape())
        .scaleEffect(state.isExpanded || state.isCompact ? 1.0 : 0.22, anchor: .top)
        .opacity(state.isExpanded || state.isCompact ? 1.0 : 0.0)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: state.isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.isCompact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(timer) { date in
            currentTime = date
            calendarEvents.refreshIfNeeded(now: date)
        }
        .onAppear {
            if showClockWidget {
                calendarEvents.start()
            }
        }
        .onChange(of: state.isExpanded) { _, isExpanded in
            if !isExpanded {
                mirror.stop()
            } else if showClockWidget {
                calendarEvents.start()
            }
        }
        .onChange(of: state.isCompact) { _, isCompact in
            if isCompact {
                mirror.stop()
            }
        }
        .onChange(of: showClockWidget) { _, isVisible in
            if isVisible {
                calendarEvents.start()
            }
        }
        .onChange(of: showMirrorWidget) { _, isVisible in
            if !isVisible {
                mirror.stop()
            }
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
                case .pomodoro:
                    PomodoroWidget(service: pomodoro)
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

    private var activeWidgets: [PanelWidget] {
        var widgets: [PanelWidget] = []

        if showNowPlayingWidget {
            widgets.append(.nowPlaying)
        }
        if showClockWidget {
            widgets.append(.clock)
        }
        if showPomodoroWidget {
            widgets.append(.pomodoro)
        }
        if showMirrorWidget {
            widgets.append(.mirror)
        }

        return widgets
    }
}

private enum PanelWidget: Hashable {
    case nowPlaying
    case clock
    case pomodoro
    case mirror
}

private struct PanelChromeControls: View {
    let onOpenSettings: () -> Void

    var body: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 28)
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
