import SwiftUI
import AVFoundation
import AppKit

struct ClockWidget: View {
    let date: Date
    @ObservedObject var calendarEvents: CalendarEventService
    private let headerHeight: CGFloat = 43

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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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

                Spacer(minLength: 8)

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
                        eventDetails(for: event)

                        if calendarEvents.upcomingEvents.count > 1 {
                            compactEventRow(for: calendarEvents.upcomingEvents[1])
                        }
                    }
                } else if case .authorized = calendarEvents.authorizationState {
                    EmptyCalendarEventsView()
                } else {
                    HStack(alignment: .center, spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(eventTint)
                            .frame(width: 12)

                        Text(eventSummary)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(eventTint)
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
        @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
        @AppStorage(BangBarSettings.Key.tintWalkingMan) private var tintWalkingMan = true
        private var accentColor: Color { Color(hex: accentColorHex) }

        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                LoopingVideoView(resourceName: "man")
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

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> VideoContainerView {
            let view = VideoContainerView()
            view.playerLayer.videoGravity = .resizeAspect
            return view
        }

        func updateNSView(_ view: VideoContainerView, context: Context) {
            guard context.coordinator.player == nil,
                  let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
                return
            }

            let item = Self.loopingItem(from: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
            context.coordinator.player = player
            context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
            view.playerLayer.player = player
            player.play()
        }

        private static func loopingItem(from url: URL) -> AVPlayerItem {
            let asset = AVURLAsset(url: url)
            let composition = AVMutableComposition()

            guard let sourceTrack = asset.tracks(withMediaType: .video).first,
                  let compositionTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                return AVPlayerItem(url: url)
            }

            let frameRate = max(Double(sourceTrack.nominalFrameRate), 1)
            let frameDuration = CMTime(seconds: 1 / frameRate, preferredTimescale: sourceTrack.timeRange.duration.timescale)
            let duration = CMTimeMaximum(.zero, sourceTrack.timeRange.duration - frameDuration)
            let timeRange = CMTimeRange(start: sourceTrack.timeRange.start, duration: duration)

            do {
                try compositionTrack.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
                compositionTrack.preferredTransform = sourceTrack.preferredTransform
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

    private func eventDetails(for event: UpcomingCalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(timeString(from: event.startDate))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(eventTint)
                    .monospacedDigit()

                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(eventTint)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }

            Text(relativeEventStatus(for: event))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint(for: event).opacity(0.85))
                .frame(width: 2)
        }
    }

    private func compactEventRow(for event: UpcomingCalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(timeString(from: event.startDate))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(tint(for: event).opacity(0.5))
                    .monospacedDigit()

                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint(for: event).opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }

            Text(relativeEventStatus(for: event))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint(for: event).opacity(0.75))
                .frame(width: 2)
        }
    }

    private var eventTint: Color {
        guard let event = calendarEvents.nextEvent,
              case .authorized = calendarEvents.authorizationState else {
            return .white.opacity(0.48)
        }

        return Color(nsColor: event.calendarColor).opacity(0.9)
    }

    private func tint(for event: UpcomingCalendarEvent) -> Color {
        Color(nsColor: event.calendarColor)
    }

    private func relativeEventStatus(for event: UpcomingCalendarEvent) -> String {
        if date < event.startDate {
            return "starts in \(minutesBetween(date, event.startDate)) min"
        }

        return "ends in \(minutesBetween(date, event.endDate)) min"
    }

    private func minutesBetween(_ start: Date, _ end: Date) -> Int {
        max(Int(ceil(end.timeIntervalSince(start) / 60)), 0)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

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

    private var eventSummary: String {
        switch calendarEvents.authorizationState {
        case .unknown, .requesting:
            return "Allow calendar access"
        case .denied:
            return "Open Calendar settings"
        case .failed:
            return "Calendar access failed"
        case .authorized:
            break
        }

        guard let event = calendarEvents.nextEvent else {
            return "No more today"
        }

        let title = event.title.isEmpty ? "Untitled" : event.title
        return "\(timeString(from: event.startDate))  \(title)"
    }
}
