import SwiftUI
import AppKit

struct NowPlayingWidget: View {
    @ObservedObject var service: NowPlayingService
    let hideArtwork: Bool
    let isActive: Bool

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    private var accentColor: Color { Color(hex: accentColorHex) }

    @State private var dragPosition: Double? = nil
    @State private var barWidth: CGFloat = 0
    @State private var isArtworkHovered = false

    private var title: String {
        service.isAvailable ? service.info.title : "No player open"
    }

    private var subtitle: String {
        service.isAvailable ? service.info.artist : "Ready when music starts"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let artwork = service.info.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ArtworkPlaceholder()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { service.openPlayer() }

                if service.info.canFavorite && (service.info.isFavorited || isArtworkHovered) {
                    FavoriteCorner(isFavorited: service.info.isFavorited, color: accentColor) {
                        service.toggleFavorite()
                    }
                    .transition(.opacity)
                }
            }
            .frame(
                width: PanelLayout.nowPlayingArtworkSize,
                height: PanelLayout.nowPlayingArtworkSize
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(hideArtwork ? 0.0 : 1.0)
            .transaction { transaction in
                transaction.animation = nil
            }
            .onHover { isArtworkHovered = $0 }
            .allowsHitTesting(!hideArtwork)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                if service.info.duration > 0 {
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            let displayPos = dragPosition ?? service.info.position
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: geo.size.width, height: 3)
                                Capsule()
                                    .fill(accentColor)
                                    .frame(width: geo.size.width * min(displayPos / service.info.duration, 1), height: 3)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear { barWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in barWidth = w }
                        }
                        .frame(height: 3)

                        HStack {
                            Text(formatTime(dragPosition ?? service.info.position))
                            Spacer()
                            Text(formatTime(service.info.duration))
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard barWidth > 0 else { return }
                                let fraction = max(0, min(value.location.x / barWidth, 1))
                                dragPosition = fraction * service.info.duration
                            }
                            .onEnded { value in
                                guard barWidth > 0 else { return }
                                let fraction = max(0, min(value.location.x / barWidth, 1))
                                service.seek(to: fraction * service.info.duration)
                                dragPosition = nil
                            }
                    )
                }

                HStack(spacing: 20) {
                    Button(action: { service.previousTrack() }) {
                        Image(systemName: "backward.fill")
                    }
                    Button(action: { service.togglePlayPause() }) {
                        Image(systemName: service.info.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    Button(action: { service.nextTrack() }) {
                        Image(systemName: "forward.fill")
                    }
                    Button(action: { service.toggleShuffle() }) {
                        Image(systemName: "shuffle")
                            .foregroundStyle(service.info.shuffleEnabled ? Color.white : Color.white.opacity(0.35))
                    }
                    .disabled(!service.canControlPlayer)
                    Button(action: { service.cycleRepeat() }) {
                        Image(systemName: service.info.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(service.info.repeatMode == .off ? Color.white.opacity(0.35) : Color.white)
                    }
                    .disabled(!service.canControlPlayer)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(service.canControlPlayback ? 1.0 : 0.35))
                .font(.system(size: 15))
                .disabled(!service.canControlPlayback)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
        }
        .frame(
            width: PanelLayout.nowPlayingWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .onAppear {
            service.setPositionUpdatesRequested(isActive)
        }
        .onChange(of: isActive) { _, isActive in
            service.setPositionUpdatesRequested(isActive)
        }
        .onDisappear {
            service.setPositionUpdatesRequested(false)
        }
    }
}

private struct FavoriteCorner: View {
    let isFavorited: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                FavoriteCornerShape()
                    .fill(color)

                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 5)
                    .padding(.trailing, 5)
            }
            .frame(width: 34, height: 34)
            .contentShape(FavoriteCornerShape())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorited ? "Remove from Favorites" : "Add to Favorites")
    }
}

private struct FavoriteCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: 0, y: 0),
                control1: CGPoint(x: rect.width * 0.72, y: rect.height * 0.72),
                control2: CGPoint(x: rect.width * 0.34, y: rect.height * 0.30)
            )
            path.closeSubpath()
        }
    }
}

struct ArtworkPlaceholder: View {
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.06, blue: 0.07)
            Circle()
                .fill(accentColor.opacity(0.25))
                .frame(width: 38, height: 38)
                .blur(radius: 14)
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(accentColor)
                .shadow(color: accentColor.opacity(0.5), radius: 4)
        }
    }
}

struct CompactNowPlayingWidget: View {
    @ObservedObject var service: NowPlayingService
    let artworkRevealAllowed: Bool
    let indicatorRevealAllowed: Bool
    let animateArtworkReveal: Bool
    let hideArtwork: Bool

    @AppStorage(BangBarSettings.Key.musicVisualizerMode)
    private var musicVisualizerModeRaw = MusicVisualizerMode.animated.rawValue
    @State private var artworkRevealIsReady = false
    @State private var indicatorRevealIsReady = false
    @State private var revealTask: Task<Void, Never>?
    private let revealDelay: Duration = .milliseconds(60)

    var body: some View {
        GeometryReader { geo in
            let artworkSize = PanelLayout.compactArtworkSize(forHeight: geo.size.height)
            let indicatorHeight = min(max(geo.size.height - 16, 14), 20)
            let horizontalPadding = PanelLayout.compactHorizontalPadding
            let indicatorWidth: CGFloat = 28
            let minimumArtworkGap: CGFloat = 34
            let hasEnoughCompactContentSpace = geo.size.width >= horizontalPadding * 2 + artworkSize + indicatorWidth + minimumArtworkGap
            let shouldShowArtwork = artworkRevealAllowed && hasEnoughCompactContentSpace && artworkRevealIsReady && !hideArtwork
            let shouldShowIndicator = indicatorRevealAllowed && hasEnoughCompactContentSpace && indicatorRevealIsReady

            ZStack {
                HStack {
                    artworkView
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: PanelLayout.compactArtworkCornerRadius(forSize: artworkSize)))
                        .scaleEffect(shouldShowArtwork ? 1.0 : 0.28)
                        .opacity(shouldShowArtwork ? 1.0 : 0.0)
                        .onTapGesture { service.openPlayer() }
                        .allowsHitTesting(shouldShowArtwork)
                    Spacer()
                }
                HStack {
                    Spacer()
                    LivePlayingIndicator(
                        levels: service.audioLevels,
                        isPlaying: service.info.isPlaying,
                        maxHeight: indicatorHeight,
                        isLive: musicVisualizerMode == .live
                    )
                        .frame(width: indicatorWidth, height: indicatorHeight)
                        .scaleEffect(shouldShowIndicator ? 1.0 : 0.28)
                        .opacity(shouldShowIndicator ? 1.0 : 0.0)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(animateArtworkReveal ? .easeOut(duration: 0.18) : nil, value: shouldShowArtwork)
            .animation(.easeOut(duration: 0.18), value: shouldShowIndicator)
            .onChange(of: hasEnoughCompactContentSpace) { _, _ in
                scheduleReveal(
                    artworkAllowed: artworkRevealAllowed, artworkHasSpace: hasEnoughCompactContentSpace,
                    indicatorAllowed: indicatorRevealAllowed, indicatorHasSpace: hasEnoughCompactContentSpace
                )
            }
            .onChange(of: indicatorRevealAllowed) { _, _ in
                scheduleReveal(
                    artworkAllowed: artworkRevealAllowed, artworkHasSpace: hasEnoughCompactContentSpace,
                    indicatorAllowed: indicatorRevealAllowed, indicatorHasSpace: hasEnoughCompactContentSpace
                )
            }
            .onChange(of: artworkRevealAllowed) { _, _ in
                scheduleReveal(
                    artworkAllowed: artworkRevealAllowed, artworkHasSpace: hasEnoughCompactContentSpace,
                    indicatorAllowed: indicatorRevealAllowed, indicatorHasSpace: hasEnoughCompactContentSpace
                )
            }
            .onChange(of: shouldShowIndicator) { _, isVisible in
                updateAudioLevelMonitoring(indicatorIsVisible: isVisible)
            }
            .onChange(of: musicVisualizerModeRaw) { _, _ in
                updateAudioLevelMonitoring(indicatorIsVisible: shouldShowIndicator)
            }
            .onAppear {
                scheduleReveal(
                    artworkAllowed: artworkRevealAllowed, artworkHasSpace: hasEnoughCompactContentSpace,
                    indicatorAllowed: indicatorRevealAllowed, indicatorHasSpace: hasEnoughCompactContentSpace
                )
                updateAudioLevelMonitoring(indicatorIsVisible: shouldShowIndicator)
            }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
                service.setAudioLevelMonitoringRequested(false)
            }
        }
    }

    private var musicVisualizerMode: MusicVisualizerMode {
        MusicVisualizerMode(rawValue: musicVisualizerModeRaw) ?? .animated
    }

    private var artworkView: some View {
        Group {
            if let artwork = service.info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ArtworkPlaceholder()
            }
        }
    }

    private func scheduleReveal(
        artworkAllowed: Bool, artworkHasSpace: Bool,
        indicatorAllowed: Bool, indicatorHasSpace: Bool
    ) {
        revealTask?.cancel()

        let shouldRevealArtwork = artworkAllowed && artworkHasSpace
        let shouldRevealIndicator = indicatorAllowed && indicatorHasSpace

        if !shouldRevealArtwork { artworkRevealIsReady = false }
        if !shouldRevealIndicator { indicatorRevealIsReady = false }

        if shouldRevealArtwork && !animateArtworkReveal {
            artworkRevealIsReady = true
        }

        guard shouldRevealArtwork || shouldRevealIndicator else {
            revealTask = nil
            return
        }

        revealTask = Task { @MainActor in
            try? await Task.sleep(for: revealDelay)
            guard !Task.isCancelled else { return }
            if animateArtworkReveal {
                artworkRevealIsReady = shouldRevealArtwork
            }
            indicatorRevealIsReady = shouldRevealIndicator
        }
    }

    private func updateAudioLevelMonitoring(indicatorIsVisible: Bool) {
        service.setAudioLevelMonitoringRequested(
            indicatorIsVisible && musicVisualizerMode == .live
        )
    }
}

struct ArtworkHeroView: View {
    @ObservedObject var service: NowPlayingService
    let progress: CGFloat
    let panelSize: CGSize

    var body: some View {
        let p = min(max(progress, 0), 1)
        let compactSize = PanelLayout.compactArtworkSize(forHeight: panelSize.height)
        let compactPadding = PanelLayout.compactHorizontalPadding
        let expandedSize: CGFloat = PanelLayout.nowPlayingArtworkSize

        let startFrame = CGRect(
            x: compactPadding,
            y: (panelSize.height - compactSize) / 2,
            width: compactSize,
            height: compactSize
        )
        let endFrame = CGRect(
            x: PanelLayout.expandedHorizontalPadding,
            y: panelSize.height - PanelLayout.expandedVisibleEdgePadding - expandedSize,
            width: expandedSize,
            height: expandedSize
        )
        let frame = interpolate(from: startFrame, to: endFrame, progress: p)
        let cornerRadius = interpolate(from: PanelLayout.compactArtworkCornerRadius(forSize: compactSize), to: 12, progress: p)

        artworkView
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .position(x: frame.midX, y: frame.midY)
            .opacity(service.isAvailable ? 1 : 0)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private var artworkView: some View {
        Group {
            if let artwork = service.info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ArtworkPlaceholder()
            }
        }
    }

    private func interpolate(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: interpolate(from: start.minX, to: end.minX, progress: progress),
            y: interpolate(from: start.minY, to: end.minY, progress: progress),
            width: interpolate(from: start.width, to: end.width, progress: progress),
            height: interpolate(from: start.height, to: end.height, progress: progress)
        )
    }

    private func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

/// Observes only the audio levels, so 12.5 Hz level updates re-render the bars and not the whole compact widget.
private struct LivePlayingIndicator: View {
    @ObservedObject var levels: LiveAudioLevels
    let isPlaying: Bool
    let maxHeight: CGFloat
    let isLive: Bool

    var body: some View {
        PlayingIndicator(isPlaying: isPlaying, maxHeight: maxHeight, liveLevels: isLive ? levels.values : nil)
    }
}

struct PlayingIndicator: View {
    let isPlaying: Bool
    let maxHeight: CGFloat
    let liveLevels: [Double]?

    @State private var isAnimating = false
    private let idleHeights: [CGFloat] = [0.46, 0.68, 0.86, 0.58]
    private let activeHeights: [CGFloat] = [0.88, 0.42, 0.72, 0.96]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(idleHeights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(playingOpacity))
                    .frame(width: 2.5, height: maxHeight)
                    .scaleEffect(y: heightMultiplier(for: index), anchor: .bottom)
                    .animation(
                        animation(for: index),
                        value: animationValue(for: index)
                    )
            }
        }
        .onAppear {
            isAnimating = isPlaying
        }
        .onChange(of: isPlaying) { _, newValue in
            isAnimating = newValue
        }
    }

    private func heightMultiplier(for index: Int) -> CGFloat {
        guard isPlaying else { return idleHeights[index] }
        if let liveLevels, liveLevels.indices.contains(index) {
            return 0.08 + CGFloat(liveLevels[index]) * 0.92
        }
        return isAnimating ? activeHeights[index] : idleHeights[index]
    }

    private func animation(for index: Int) -> Animation {
        if liveLevels != nil {
            return .linear(duration: 0.1)
        }
        return isPlaying
            ? .easeInOut(duration: 0.46 + Double(index) * 0.08)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.07)
            : .easeOut(duration: 0.18)
    }

    private func animationValue(for index: Int) -> CGFloat {
        heightMultiplier(for: index)
    }

    private var playingOpacity: Double {
        guard isPlaying else { return 0.16 }
        return liveLevels == nil ? 0.36 : 0.58
    }
}

/// `m:ss`
func formatTime(_ seconds: Double) -> String {
    let s = Int(max(seconds, 0))
    return String(format: "%d:%02d", s / 60, s % 60)
}
