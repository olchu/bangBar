import SwiftUI
import Combine

struct PanelContentView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var nowPlaying: NowPlayingService
    @StateObject private var mirror = MirrorCameraService()
    @StateObject private var calendarEvents = CalendarEventService()
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
                        NowPlayingWidget(
                            service: nowPlaying,
                            hideArtwork: hideExpandedArtwork
                        )
                        .frame(
                            width: PanelLayout.nowPlayingWidgetWidth,
                            height: PanelLayout.nowPlayingWidgetHeight,
                            alignment: .topLeading
                        )

                        Divider()
                            .background(Color.white.opacity(0.2))
                            .frame(
                                width: PanelLayout.expandedDividerWidth,
                                height: PanelLayout.expandedDividerHeight
                            )

                        ClockWidget(date: currentTime, calendarEvents: calendarEvents)
                            .frame(width: PanelLayout.clockWidgetWidth, alignment: .leading)
                            .offset(x: -8)

                        Divider()
                            .background(Color.white.opacity(0.2))
                            .frame(
                                width: PanelLayout.expandedDividerWidth,
                                height: PanelLayout.expandedDividerHeight
                            )

                        MirrorWidget(service: mirror)
                            .frame(
                                width: PanelLayout.mirrorWidgetWidth,
                                height: PanelLayout.mirrorWidgetHeight
                            )
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
            calendarEvents.start()
        }
        .onChange(of: state.isExpanded) { _, isExpanded in
            if !isExpanded {
                mirror.stop()
            } else {
                calendarEvents.start()
            }
        }
        .onChange(of: state.isCompact) { _, isCompact in
            if isCompact {
                mirror.stop()
            }
        }
    }
}
