import SwiftUI
import Combine

final class PanelState: ObservableObject {
    @Published var isExpanded = false
    @Published var contentVisible = false
}

struct PanelContentView: View {
    @ObservedObject var state: PanelState
    @StateObject private var nowPlaying = NowPlayingService()
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black

            HStack(spacing: 20) {
                ClockWidget(date: currentTime)

                Divider()
                    .background(Color.white.opacity(0.2))
                    .frame(height: 70)

                NowPlayingWidget(service: nowPlaying, date: currentTime)
            }
            .padding(.horizontal, 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(state.contentVisible ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.18), value: state.contentVisible)
        }
        .clipShape(NotchPanelShape())
        .scaleEffect(state.isExpanded ? 1.0 : 0.22, anchor: .top)
        .opacity(state.isExpanded ? 1.0 : 0.0)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: state.isExpanded)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Время")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)

            Text(timeString)
                .font(.system(size: 32, weight: .thin, design: .monospaced))
                .foregroundColor(.white)
        }
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
            HStack(spacing: 12) {
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
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.info.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(service.info.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
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
            }
            .frame(minWidth: 200, alignment: .leading)
        } else {
            CalendarWidget(date: date)
        }
    }
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
    var topRadius: CGFloat = 22
    var bottomRadius: CGFloat = 22
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
