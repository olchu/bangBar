import SwiftUI
import Combine
import AVFoundation

enum PanelLayout {
    static let expandedHeight: CGFloat = 155
    static let panelTopRadius: CGFloat = 22
    static let panelTopEarInset: CGFloat = 22
    static let compactMinimumWidth: CGFloat = 320
    static let compactNotchSidePadding: CGFloat = 100
    static let compactMaximumWidth: CGFloat = 360
    static let expandedVisibleEdgePadding: CGFloat = 20
    static let expandedHorizontalPadding: CGFloat = panelTopEarInset + panelTopRadius + expandedVisibleEdgePadding
    static let expandedWidgetSpacing: CGFloat = 20
    static let expandedDividerWidth: CGFloat = 1
    static let expandedDividerHeight: CGFloat = 70

    static let nowPlayingWidgetWidth: CGFloat = 300
    static let nowPlayingWidgetHeight: CGFloat = 110
    static let nowPlayingArtworkSize: CGFloat = 110
    static let mirrorWidgetWidth: CGFloat = 94
    static let mirrorWidgetHeight: CGFloat = 94
    static let clockWidgetWidth: CGFloat = 170
    static let calendarWidgetWidth: CGFloat = 140

    static let expandedWidgetWidths: [CGFloat] = [
        nowPlayingWidgetWidth,
        expandedDividerWidth,
        clockWidgetWidth,
        expandedDividerWidth,
        mirrorWidgetWidth
    ]

    static var expandedWidth: CGFloat {
        let contentWidth = expandedWidgetWidths.reduce(0, +)
        let spacingWidth = expandedWidgetSpacing * CGFloat(max(expandedWidgetWidths.count - 1, 0))
        return expandedHorizontalPadding * 2 + contentWidth + spacingWidth
    }

    static func compactHorizontalPadding(for height: CGFloat) -> CGFloat {
        min(max(height + 18, 50), 50)
    }

    static func compactWidth(for notchWidth: CGFloat) -> CGFloat {
        min(max(notchWidth + compactNotchSidePadding * 2, compactMinimumWidth), compactMaximumWidth)
    }
}

final class PanelState: ObservableObject {
    @Published var isExpanded = false
    @Published var isCompact = false
    @Published var contentVisible = false
    @Published var compactArtworkRevealAllowed = true
    @Published var compactIndicatorRevealAllowed = true
    @Published var compactArtworkRevealAnimated = true
    @Published var artworkHeroProgress: CGFloat?
}

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

// MARK: - Widgets

struct ClockWidget: View {
    let date: Date
    @ObservedObject var calendarEvents: CalendarEventService
    private let dateColumnWidth: CGFloat = 44

    private var hourString: String {
        let f = DateFormatter()
        f.dateFormat = "HH"
        return f.string(from: date)
    }

    private var minuteString: String {
        let f = DateFormatter()
        f.dateFormat = "mm"
        return f.string(from: date)
    }

    private var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private var monthString: String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateFormat = "MMM"
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private var weekdayString: String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateFormat = "EEE"
        return f.string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(hourString)
                Text(":")
                    .foregroundStyle(.white.opacity(0.42))
                    .offset(y: -1)
                Text(minuteString)
            }
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.94))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .fixedSize(horizontal: true, vertical: false)

            dateColumn
                .frame(
                    width: PanelLayout.clockWidgetWidth,
                    height: PanelLayout.nowPlayingWidgetHeight,
                    alignment: .trailing
                )

            eventLine
                .frame(
                    width: PanelLayout.clockWidgetWidth - dateColumnWidth - 14,
                    alignment: .leading
                )
                .frame(
                    width: PanelLayout.clockWidgetWidth,
                    height: PanelLayout.nowPlayingWidgetHeight,
                    alignment: .bottomLeading
                )
        }
        .padding(.top, 2)
        .frame(
            width: PanelLayout.clockWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
    }

    private var eventLine: some View {
        Button(action: { calendarEvents.requestAccessFromUserAction() }) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
                    .frame(width: 12)
                    .padding(.top, 1)

                Text(eventSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dateColumn: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(weekdayString)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black.opacity(0.82))
                .frame(width: dateColumnWidth, height: 27, alignment: .center)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.84))
                )

            Text(dayString)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: dateColumnWidth, alignment: .center)

            Text(monthString.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(width: dateColumnWidth, alignment: .center)
                .offset(x: 1)
        }
        .frame(width: dateColumnWidth, alignment: .center)
    }

    private var eventSummary: String {
        if calendarEvents.authorizationDenied {
            return "Calendar access needed"
        }

        guard let event = calendarEvents.nextEvent else {
            return "No more today"
        }

        let f = DateFormatter()
        f.dateFormat = "HH:mm"

        let title = event.title.isEmpty ? "Untitled" : event.title
        return "\(f.string(from: event.startDate))  \(title)"
    }
}

struct CalendarWidget: View {
    let date: Date

    var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var monthString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL"
        return f.string(from: date).capitalized
    }

    var weekdayString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE"
        return f.string(from: date).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Дата")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayString)
                    .font(.system(size: 40, weight: .thin))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monthString)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white)
                    Text(weekdayString)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(width: PanelLayout.calendarWidgetWidth, alignment: .leading)
    }
}

struct MirrorWidget: View {
    @ObservedObject var service: MirrorCameraService

    var body: some View {
        ZStack {
            if service.state == .running {
                CameraPreviewView(session: service.session)
                    .scaleEffect(x: -1, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color.white.opacity(0.10), radius: 10)
                    .transition(.scale(scale: 0.62).combined(with: .opacity))
            }

            if service.state == .running {
                Button(action: { service.toggle() }) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(2)
            } else {
                Button(action: { service.toggle() }) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.045)
                                    ],
                                    center: .topLeading,
                                    startRadius: 4,
                                    endRadius: 34
                                )
                            )
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))

                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(iconColor)

                        statusDot
                            .offset(x: 16, y: -16)
                    }
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: service.state)
        .onDisappear {
            service.stop()
        }
    }

    private var iconName: String {
        switch service.state {
        case .off:
            return "video.fill"
        case .requesting:
            return "video.badge.ellipsis"
        case .running:
            return "video.fill"
        case .stopping:
            return "video.slash.fill"
        case .denied, .failed:
            return "video.slash.fill"
        }
    }

    private var iconColor: Color {
        switch service.state {
        case .denied, .failed:
            return .white.opacity(0.35)
        case .requesting, .stopping:
            return .white.opacity(0.55)
        case .off, .running:
            return .white.opacity(0.72)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch service.state {
        case .requesting, .stopping:
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 7, height: 7)
        case .denied, .failed:
            Circle()
                .fill(Color.red.opacity(0.72))
                .frame(width: 7, height: 7)
        case .off, .running:
            EmptyView()
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: CameraPreviewContainerView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class CameraPreviewContainerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

struct NowPlayingWidget: View {
    @ObservedObject var service: NowPlayingService
    let hideArtwork: Bool

    private var title: String {
        service.isAvailable ? service.info.title : "No player open"
    }

    private var subtitle: String {
        service.isAvailable ? service.info.artist : "Ready when music starts"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let artwork = service.info.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ArtworkPlaceholder()
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
            .onTapGesture { service.openPlayer() }
            .allowsHitTesting(service.isAvailable && !hideArtwork)

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
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: geo.size.width * min(service.info.position / service.info.duration, 1), height: 3)
                            }
                        }
                        .frame(height: 3)

                        HStack {
                            Text(formatTime(service.info.position))
                            Spacer()
                            Text(formatTime(service.info.duration))
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    }
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
                    Button(action: { service.cycleRepeat() }) {
                        Image(systemName: service.info.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(service.info.repeatMode == .off ? Color.white.opacity(0.35) : Color.white)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(service.isAvailable ? 1.0 : 0.35))
                .font(.system(size: 15))
                .disabled(!service.isAvailable)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
        }
        .frame(
            width: PanelLayout.nowPlayingWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
    }
}

struct ArtworkPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
        }
    }
}

struct CompactNowPlayingWidget: View {
    @ObservedObject var service: NowPlayingService
    let artworkRevealAllowed: Bool
    let indicatorRevealAllowed: Bool
    let animateArtworkReveal: Bool
    let hideArtwork: Bool

    @State private var artworkRevealIsReady = false
    @State private var indicatorRevealIsReady = false
    @State private var revealTask: Task<Void, Never>?
    private let revealDelay: Duration = .milliseconds(60)

    var body: some View {
        GeometryReader { geo in
            let artworkSize = min(max(geo.size.height - 10, 22), 32)
            let indicatorHeight = min(max(geo.size.height - 16, 14), 20)
            let horizontalPadding = PanelLayout.compactHorizontalPadding(for: geo.size.height)
            let indicatorWidth: CGFloat = 28
            let minimumArtworkGap: CGFloat = 34
            let hasEnoughCompactContentSpace = geo.size.width >= horizontalPadding * 2 + artworkSize + indicatorWidth + minimumArtworkGap
            let shouldShowArtwork = artworkRevealAllowed && hasEnoughCompactContentSpace && artworkRevealIsReady && !hideArtwork
            let shouldShowIndicator = indicatorRevealAllowed && hasEnoughCompactContentSpace && indicatorRevealIsReady

            ZStack {
                HStack {
                    artworkView
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: min(7, artworkSize / 4)))
                        .scaleEffect(shouldShowArtwork ? 1.0 : 0.28)
                        .opacity(shouldShowArtwork ? 1.0 : 0.0)
                        .onTapGesture { service.openPlayer() }
                        .allowsHitTesting(shouldShowArtwork)
                    Spacer()
                }
                HStack {
                    Spacer()
                    PlayingIndicator(isPlaying: service.info.isPlaying, maxHeight: indicatorHeight)
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
            .onAppear {
                scheduleReveal(
                    artworkAllowed: artworkRevealAllowed, artworkHasSpace: hasEnoughCompactContentSpace,
                    indicatorAllowed: indicatorRevealAllowed, indicatorHasSpace: hasEnoughCompactContentSpace
                )
            }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
            }
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = service.info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
                    .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.45)))
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
}

struct ArtworkHeroView: View {
    @ObservedObject var service: NowPlayingService
    let progress: CGFloat
    let panelSize: CGSize

    var body: some View {
        let p = min(max(progress, 0), 1)
        let compactSize = min(max(panelSize.height - 10, 22), 32)
        let compactPadding = PanelLayout.compactHorizontalPadding(for: panelSize.height)
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
        let cornerRadius = interpolate(from: min(7, compactSize / 4), to: 12, progress: p)

        artworkView
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .position(x: frame.midX, y: frame.midY)
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
                Color.white.opacity(0.08)
                    .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.45)))
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

struct PlayingIndicator: View {
    let isPlaying: Bool
    let maxHeight: CGFloat

    @State private var isAnimating = false
    private let idleHeights: [CGFloat] = [0.46, 0.68, 0.86, 0.58]
    private let activeHeights: [CGFloat] = [0.88, 0.42, 0.72, 0.96]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(idleHeights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(isPlaying ? 0.36 : 0.16))
                    .frame(width: 2.5, height: maxHeight * heightMultiplier(for: index))
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 0.46 + Double(index) * 0.08)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.07)
                            : .easeOut(duration: 0.18),
                        value: isAnimating
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
        return isAnimating ? activeHeights[index] : idleHeights[index]
    }
}

private func formatTime(_ seconds: Double) -> String {
    let s = Int(max(seconds, 0))
    return String(format: "%d:%02d", s / 60, s % 60)
}

struct SystemWidget: View {
    @State private var batteryLevel: Float = 0.78
    @State private var isCharging = false

    var batteryColor: Color {
        batteryLevel > 0.5 ? .green : batteryLevel > 0.2 ? .yellow : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Система")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                StatRow(label: "Батарея", value: "\(Int(batteryLevel * 100))%", color: batteryColor)
                StatRow(label: "Память", value: "6.2 ГБ", color: .blue)
                StatRow(label: "CPU", value: "12%", color: .orange)
            }
        }
        .frame(minWidth: 130, alignment: .leading)
        .onAppear {
            batteryLevel = Float.random(in: 0.3...0.99)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 65, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: - Notch Panel Shape

struct NotchPanelShape: Shape {
    var topRadius: CGFloat = PanelLayout.panelTopRadius
    var bottomRadius: CGFloat = 26
    var topEarInset: CGFloat = PanelLayout.panelTopEarInset

    func path(in rect: CGRect) -> Path {
        var p = Path()

        let topRadius = min(topRadius, min(rect.width, rect.height) / 2)
        let bottomRadius = min(bottomRadius, min(rect.width, rect.height) / 2)
        let topEarInset = min(topEarInset, rect.width / 4)
        let minX = rect.minX + topEarInset
        let maxX = rect.maxX - topEarInset

        p.move(to: CGPoint(x: minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: minX + topRadius, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: minX + topRadius, y: rect.maxY - bottomRadius))
        p.addQuadCurve(
            to: CGPoint(x: minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: minX + topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: maxX - topRadius - bottomRadius, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: maxX - topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: maxX - topRadius, y: rect.minY + topRadius))
        p.addQuadCurve(
            to: CGPoint(x: maxX, y: rect.minY),
            control: CGPoint(x: maxX - topRadius, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: minX, y: rect.minY))
        p.closeSubpath()

        return p
    }
}
