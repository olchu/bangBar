import SwiftUI
import AVFoundation
import AppKit

struct ClockWidget: View {
    let date: Date
    @ObservedObject var calendarEvents: CalendarEventService
    let isPanelContentVisible: Bool
    private let headerHeight: CGFloat = 43

    private var hourString: String {
        Self.hourFormatter.string(from: date)
    }

    private var minuteString: String {
        Self.minuteFormatter.string(from: date)
    }

    private var dayString: String {
        Self.dayFormatter.string(from: date)
    }

    private var monthString: String {
        Self.monthFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private var weekdayString: String {
        Self.weekdayFormatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter
    }()

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(hourString)
                    Text(":")
                        .foregroundStyle(.white.opacity(0.42))
                        .offset(y: -1)
                    Text(minuteString)
                }
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 4)

                inlineDate
            }
            .frame(height: headerHeight, alignment: .top)

            eventLine
                .frame(
                    width: PanelLayout.clockWidgetWidth,
                    alignment: .leading
                )
        }
        .frame(
            width: PanelLayout.clockWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
    }

    private var eventLine: some View {
        Button(action: { calendarEvents.requestAccessFromUserAction() }) {
            Group {
                if let event = calendarEvents.nextEvent,
                   case .authorized = calendarEvents.authorizationState {
                    VStack(alignment: .leading, spacing: 4) {
                        eventRow(for: event, isPrimary: true)

                        if calendarEvents.upcomingEvents.count > 1 {
                            eventRow(for: calendarEvents.upcomingEvents[1], isPrimary: false)
                        }
                    }
                } else if case .authorized = calendarEvents.authorizationState {
                    EmptyCalendarEventsView(isPanelContentVisible: isPanelContentVisible)
                } else {
                    HStack(alignment: .center, spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))
                            .frame(width: 12)

                        Text(accessPrompt)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct EmptyCalendarEventsView: View {
        let isPanelContentVisible: Bool

        @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
        @AppStorage(BangBarSettings.Key.tintWalkingMan) private var tintWalkingMan = true
        private var accentColor: Color { Color(hex: accentColorHex) }

        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                LoopingVideoView(resourceName: "man", isPlaying: isPanelContentVisible)
                    .frame(width: 55, height: 55)
                    .colorMultiply(tintWalkingMan ? accentColor : .white)

                VStack(alignment: .center, spacing: 3) {
                    Text("No plans")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("walking free")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        }
    }

    private struct LoopingVideoView: NSViewRepresentable {
        let resourceName: String
        let isPlaying: Bool

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> VideoContainerView {
            let view = VideoContainerView()
            view.playerLayer.videoGravity = .resizeAspect
            return view
        }

        func updateNSView(_ view: VideoContainerView, context: Context) {
            context.coordinator.wantsPlaying = isPlaying
            if let player = context.coordinator.player {
                isPlaying ? player.play() : player.pause()
                return
            }

            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else { return }

            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
            let coordinator = context.coordinator
            coordinator.player = player
            view.playerLayer.player = player
            if isPlaying {
                player.play()
            }

            Task { @MainActor in
                let item = await Self.loopingItem(from: url)
                guard coordinator.player === player else { return }
                coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
                // The queue was empty when playback was first requested; apply the latest state now that it has items.
                coordinator.wantsPlaying ? player.play() : player.pause()
            }
        }

        private static func loopingItem(from url: URL) async -> AVPlayerItem {
            let asset = AVURLAsset(url: url)
            let composition = AVMutableComposition()

            guard let sourceTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let properties = try? await sourceTrack.load(.nominalFrameRate, .timeRange, .preferredTransform),
                  let compositionTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                return AVPlayerItem(url: url)
            }

            let (nominalFrameRate, sourceRange, preferredTransform) = properties
            let frameRate = max(Double(nominalFrameRate), 1)
            let frameDuration = CMTime(seconds: 1 / frameRate, preferredTimescale: sourceRange.duration.timescale)
            let duration = CMTimeMaximum(.zero, sourceRange.duration - frameDuration)
            let timeRange = CMTimeRange(start: sourceRange.start, duration: duration)

            do {
                try compositionTrack.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
                compositionTrack.preferredTransform = preferredTransform
            } catch {
                return AVPlayerItem(url: url)
            }

            let item = AVPlayerItem(asset: composition)
            item.preferredForwardBufferDuration = 0
            return item
        }

        static func dismantleNSView(_ view: VideoContainerView, coordinator: Coordinator) {
            coordinator.player?.pause()
            coordinator.looper = nil
            coordinator.player = nil
            view.playerLayer.player = nil
        }

        final class Coordinator {
            var player: AVQueuePlayer?
            var looper: AVPlayerLooper?
            var wantsPlaying = false
        }

        final class VideoContainerView: NSView {
            let playerLayer = AVPlayerLayer()

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                wantsLayer = true
                layer?.backgroundColor = NSColor.clear.cgColor
                playerLayer.backgroundColor = NSColor.clear.cgColor
                playerLayer.masksToBounds = true
                layer?.addSublayer(playerLayer)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                nil
            }

            override func layout() {
                super.layout()
                playerLayer.frame = bounds
            }
        }
    }

    private func eventRow(for event: UpcomingCalendarEvent, isPrimary: Bool) -> some View {
        let calendarTint = tint(for: event)
        let textTint = calendarTint.opacity(isPrimary ? 0.9 : 0.5)
        let fontSize: CGFloat = isPrimary ? 11 : 10
        return VStack(alignment: .leading, spacing: isPrimary ? 3 : 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(timeString(from: event.startDate))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(textTint)
                    .monospacedDigit()

                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(textTint)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }

            Text(relativeEventStatus(for: event))
                .font(.system(size: fontSize - 2, weight: .medium))
                .foregroundStyle(.white.opacity(isPrimary ? 0.42 : 0.28))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(calendarTint.opacity(isPrimary ? 0.85 : 0.75))
                .frame(width: 2)
        }
    }

    private func tint(for event: UpcomingCalendarEvent) -> Color {
        Color(nsColor: event.calendarColor)
    }

    private func relativeEventStatus(for event: UpcomingCalendarEvent) -> String {
        if date < event.startDate {
            return "starts in \(durationString(from: date, to: event.startDate))"
        }

        return "ends in \(durationString(from: date, to: event.endDate))"
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let totalMinutes = max(Int(ceil(end.timeIntervalSince(start) / 60)), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return remainingHours > 0 ? "\(days)d \(remainingHours)h" : "\(days)d"
        }

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)min"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)min"
    }

    private func timeString(from date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    private var accentColor: Color { Color(hex: accentColorHex) }

    private var inlineDate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(weekdayString)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            Text(dayString)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .monospacedDigit()

            Text(monthString.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .fixedSize(horizontal: true, vertical: false)
        .frame(alignment: .trailing)
        .offset(y: 1)
    }

    private var accessPrompt: String {
        switch calendarEvents.authorizationState {
        case .unknown, .requesting, .authorized:
            return "Allow calendar access"
        case .denied:
            return "Open Calendar settings"
        case .failed:
            return "Calendar access failed"
        }
    }
}
