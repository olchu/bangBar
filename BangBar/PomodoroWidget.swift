import SwiftUI

struct PomodoroWidget: View {
    @ObservedObject var service: PomodoroService
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    private var accentColor: Color { Color(hex: accentColorHex) }
    private let tickCount = 72
    private let outerRadius: CGFloat = 51

    private var totalDuration: Int {
        switch service.sessionType {
        case .work:       return PomodoroService.workDuration
        case .shortBreak: return PomodoroService.shortBreakDuration
        case .longBreak:  return PomodoroService.longBreakDuration
        }
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - Double(service.secondsRemaining) / Double(totalDuration)
    }

    private var pomodoroInCycle: Int {
        if service.sessionType == .work {
            return service.completedPomodoros % 4 + 1
        }
        let mod = service.completedPomodoros % 4
        return mod == 0 ? 4 : mod
    }

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { i in
                let angle = Double(i) / Double(tickCount) * 360.0 - 90.0
                let isActive = Double(i) / Double(tickCount) < progress

                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? accentColor : accentColor.opacity(0.18))
                    .frame(width: 2, height: isActive ? 7 : 5)
                    .offset(y: -outerRadius)
                    .rotationEffect(.degrees(angle))
            }
            .allowsHitTesting(false)

            Button(action: service.togglePlayPause) {
                Color.clear
                    .frame(width: PanelLayout.pomodoroWidgetWidth, height: PanelLayout.pomodoroWidgetWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(service.isRunning ? accentColor : accentColor.opacity(0.45))
                        .frame(width: 5, height: 5)

                    Text(service.sessionLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(service.isRunning ? accentColor : accentColor.opacity(0.45))
                }

                Text(service.timeString)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .monospacedDigit()
                    .lineLimit(1)

                Text("\(pomodoroInCycle) / 4")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .offset(y: 2)
            }
            .allowsHitTesting(false)

            Button(action: service.reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, -8)
            .padding(.bottom, 6)

            Button(action: service.togglePlayPause) {
                Image(systemName: service.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, -8)
            .padding(.bottom, 6)
        }
        .frame(width: PanelLayout.pomodoroWidgetWidth, height: PanelLayout.pomodoroWidgetWidth)
    }
}

struct CompactPomodoroWidget: View {
    @ObservedObject var service: PomodoroService
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    private var accentColor: Color { Color(hex: accentColorHex) }
    private let tickCount = 28

    private var totalDuration: Int {
        switch service.sessionType {
        case .work:       return PomodoroService.workDuration
        case .shortBreak: return PomodoroService.shortBreakDuration
        case .longBreak:  return PomodoroService.longBreakDuration
        }
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - Double(service.secondsRemaining) / Double(totalDuration)
    }

    var body: some View {
        GeometryReader { geo in
            let horizontalPadding = PanelLayout.compactHorizontalPadding(for: geo.size.height)
            let iconSize = min(max(geo.size.height - 12, 20), 30)
            let hasEnoughSpace = geo.size.width >= horizontalPadding * 2 + 96

            HStack {
                VStack(alignment: .center, spacing: 1) {
                    Text(service.timeString)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .monospacedDigit()
                        .lineLimit(1)

                    Text(compactSessionLabel)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }
                .frame(width: 44, height: geo.size.height, alignment: .center)
                .opacity(hasEnoughSpace ? 1.0 : 0.0)

                Spacer(minLength: 56)

                CompactPomodoroProgressRing(
                    progress: progress,
                    accentColor: accentColor,
                    tickCount: tickCount
                )
                .frame(width: iconSize, height: iconSize)
                .shadow(color: accentColor.opacity(0.22), radius: 5)
                .opacity(hasEnoughSpace ? 1.0 : 0.0)
                .accessibilityLabel(compactSessionLabel)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var compactSessionLabel: String {
        switch service.sessionType {
        case .work:
            return "Work"
        case .shortBreak:
            return "Break"
        case .longBreak:
            return "Rest"
        }
    }
}

private struct CompactPomodoroProgressRing: View {
    let progress: Double
    let accentColor: Color
    let tickCount: Int

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = max(size / 2 - 3, 1)

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))

                ForEach(0..<tickCount, id: \.self) { index in
                    let angle = Double(index) / Double(tickCount) * 360.0 - 90.0
                    let isActive = Double(index) / Double(tickCount) < progress

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isActive ? accentColor : accentColor.opacity(0.2))
                        .frame(width: 1.5, height: isActive ? 4.5 : 3.5)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(angle))
                }

                Circle()
                    .fill(accentColor.opacity(0.85))
                    .frame(width: max(size * 0.26, 5), height: max(size * 0.26, 5))
            }
        }
    }
}
