import SwiftUI
import Combine

struct PanelContentView: View {
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

                CalendarWidget(date: currentTime)

                Divider()
                    .background(Color.white.opacity(0.2))
                    .frame(height: 70)

                SystemWidget()
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(NotchShape(), style: FillStyle(eoFill: true))
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

    var secondsString: String {
        let f = DateFormatter()
        f.dateFormat = "ss"
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Время")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(timeString)
                    .font(.system(size: 40, weight: .thin, design: .monospaced))
                    .foregroundColor(.white)
                Text(secondsString)
                    .font(.system(size: 20, weight: .thin, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(minWidth: 130, alignment: .leading)
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

// MARK: - Notch Shape

struct NotchShape: Shape {
    var radius: CGFloat = 22
    var earRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = radius
        let er = earRadius

        // Main body: flat top, rounded bottom corners
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        p.addQuadCurve(to: CGPoint(x: rect.width - r, y: rect.height),
                       control: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: r, y: rect.height))
        p.addQuadCurve(to: CGPoint(x: 0, y: rect.height - r),
                       control: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()

        // Left ear: quarter-circle punched out at top-left corner via even-odd rule
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: er, y: 0))
        p.addArc(center: .zero, radius: er,
                 startAngle: .degrees(0), endAngle: .degrees(90),
                 clockwise: true)
        p.closeSubpath()

        // Right ear: quarter-circle punched out at top-right corner
        p.move(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width - er, y: 0))
        p.addArc(center: CGPoint(x: rect.width, y: 0), radius: er,
                 startAngle: .degrees(180), endAngle: .degrees(90),
                 clockwise: false)
        p.closeSubpath()

        return p
    }
}
