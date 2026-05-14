import SwiftUI
import Combine

final class PanelState: ObservableObject {
    @Published var isExpanded = false
    @Published var isCompact = false
    @Published var contentVisible = false
    @Published var compactArtworkRevealAllowed = true
    @Published var compactIndicatorRevealAllowed = true
}

struct PanelContentView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var nowPlaying: NowPlayingService
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black

            if state.isCompact {
                CompactNowPlayingWidget(
                    service: nowPlaying,
                    artworkRevealAllowed: state.compactArtworkRevealAllowed,
                    indicatorRevealAllowed: state.compactIndicatorRevealAllowed
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                HStack(spacing: 20) {
                    NowPlayingWidget(service: nowPlaying, date: currentTime)

                    Divider()
                        .background(Color.white.opacity(0.2))
                        .frame(height: 70)

                    ClockWidget(date: currentTime)
                }
                .padding(.horizontal, 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(state.contentVisible ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.18), value: state.contentVisible)
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
        }
    }
}

// MARK: - Widgets

struct ClockWidget: View {
    let date: Date

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var body: some View {
        Text(timeString)
            .font(.system(size: 32, weight: .thin, design: .monospaced))
            .foregroundColor(.white)
            .frame(minWidth: 100, alignment: .leading)
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
        .frame(minWidth: 140, alignment: .leading)
    }
}

struct NowPlayingWidget: View {
    @ObservedObject var service: NowPlayingService
    let date: Date

    var body: some View {
        if service.isAvailable {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let artwork = service.info.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.08)
                            .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.3)))
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { service.openPlayer() }

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.info.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(service.info.artist)
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

                    HStack(spacing: 24) {
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
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .topLeading)
        } else {
            CalendarWidget(date: date)
        }
    }
}

struct CompactNowPlayingWidget: View {
    @ObservedObject var service: NowPlayingService
    let artworkRevealAllowed: Bool
    let indicatorRevealAllowed: Bool

    @State private var artworkRevealIsReady = false
    @State private var indicatorRevealIsReady = false
    @State private var revealTask: Task<Void, Never>?
    private let revealDelay: Duration = .milliseconds(60)

    var body: some View {
        GeometryReader { geo in
            let artworkSize = min(max(geo.size.height - 10, 22), 32)
            let indicatorHeight = min(max(geo.size.height - 16, 14), 20)
            let horizontalPadding = min(max(geo.size.height + 12, 42), 52)
            let indicatorWidth: CGFloat = 28
            let minimumArtworkGap: CGFloat = 34
            let hasEnoughCompactContentSpace = geo.size.width >= horizontalPadding * 2 + artworkSize + indicatorWidth + minimumArtworkGap
            let shouldShowArtwork = artworkRevealAllowed && hasEnoughCompactContentSpace && artworkRevealIsReady
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
            .animation(.easeOut(duration: 0.18), value: shouldShowArtwork)
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

        guard shouldRevealArtwork || shouldRevealIndicator else {
            revealTask = nil
            return
        }

        revealTask = Task { @MainActor in
            try? await Task.sleep(for: revealDelay)
            guard !Task.isCancelled else { return }
            artworkRevealIsReady = shouldRevealArtwork
            indicatorRevealIsReady = shouldRevealIndicator
        }
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
    var topRadius: CGFloat = 20
    var bottomRadius: CGFloat = 26
    var topEarInset: CGFloat = 18

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
