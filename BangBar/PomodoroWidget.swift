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
        }
        .frame(width: PanelLayout.pomodoroWidgetWidth, height: PanelLayout.pomodoroWidgetWidth)
    }
}
