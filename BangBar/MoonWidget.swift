import Foundation
import SwiftUI

struct MoonWidget: View {
    let date: Date
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    private var phase: MoonPhase {
        MoonPhase(date: date)
    }

    private var accentColor: Color {
        Color(hex: accentColorHex)
    }

    var body: some View {
        ZStack {
            moonProgressArc
            moonDisk

            cornerText("\(phase.illuminationPercent)%", alignment: .trailing)
                .frame(width: 38, alignment: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            cornerText(phase.fullMoonDateText, alignment: .trailing)
                .frame(width: 52, alignment: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: PanelLayout.moonWidgetWidth, height: PanelLayout.nowPlayingWidgetHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phase.name), \(phase.illuminationPercent)% visible, next full moon \(phase.fullMoonDateText)")
    }

    private func cornerText(_ text: String, alignment: TextAlignment) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .multilineTextAlignment(alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
    }

    private var moonDisk: some View {
        ZStack {
            Image("MoonTexture")
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 90)
                .saturation(0.48)
                .brightness(-0.56)

            Image("MoonTexture")
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 90)
                .saturation(0.42)
                .contrast(0.86)
                .brightness(-0.12)
                .opacity(0.92)
                .mask {
                    MoonIlluminationMask(
                        illumination: phase.illuminationFraction,
                        isWaxing: phase.isWaxing
                    )
                }
        }
        .frame(width: 90, height: 90)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.62), radius: 7, y: 2)
        .shadow(color: accentColor.opacity(0.16), radius: 14)
    }

    private var moonProgressArc: some View {
        let progress = CGFloat(phase.fullMoonCycleProgress)

        return ZStack {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.red.opacity(0.24),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
                .blur(radius: 6)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.red.opacity(0.2),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
                .blur(radius: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.red.opacity(0.52),
                    style: StrokeStyle(lineWidth: 0.65, lineCap: .round)
                )
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-90))
        }
        .allowsHitTesting(false)
    }
}

struct MoonPhase {
    private static let synodicPeriod = 29.53059
    private static let secondsPerDay = 86_400.0
    private static let j2000 = 2_451_545.0

    private let date: Date
    private let elongation: Double

    init(date: Date) {
        self.date = date
        elongation = Self.lunarElongation(on: date)
    }

    var name: String {
        switch phase {
        case .new:
            return "New moon"
        case .waxingCrescent:
            return "Waxing crescent"
        case .firstQuarter:
            return "First quarter"
        case .waxingGibbous:
            return "Waxing gibbous"
        case .full:
            return "Full moon"
        case .waningGibbous:
            return "Waning gibbous"
        case .lastQuarter:
            return "Last quarter"
        case .waningCrescent:
            return "Waning crescent"
        }
    }

    var illuminationPercent: Int {
        Int((illuminationFraction * 100).rounded())
    }

    var fullMoonDateText: String {
        Self.fullMoonDateFormatter.string(from: Self.nextFullMoon(after: date))
    }

    var fullMoonCycleProgress: Double {
        let previousFullMoon = Self.previousFullMoon(before: date)
        let nextFullMoon = Self.nextFullMoon(after: date)
        let cycleLength = nextFullMoon.timeIntervalSince(previousFullMoon)

        guard cycleLength > 0 else { return 0 }

        let progress = date.timeIntervalSince(previousFullMoon) / cycleLength
        return min(max(progress, 0), 1)
    }

    var illuminationFraction: Double {
        (1 - cos(elongation.degreesToRadians)) / 2
    }

    var isWaxing: Bool {
        elongation < 180
    }

    private var phase: Phase {
        let index = Int((elongation / 45).rounded()) % Phase.allCases.count
        return Phase.allCases[index]
    }

    private enum Phase: CaseIterable {
        case new
        case waxingCrescent
        case firstQuarter
        case waxingGibbous
        case full
        case waningGibbous
        case lastQuarter
        case waningCrescent
    }

    private static let fullMoonDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static func nextFullMoon(after date: Date) -> Date {
        let sampleStep = 6.0 * 60 * 60
        let sampleCount = Int((synodicPeriod * secondsPerDay) / sampleStep)
        var bestDate = date
        var bestIllumination = -Double.infinity

        for sample in 0...sampleCount {
            let candidate = date.addingTimeInterval(Double(sample) * sampleStep)
            let illumination = illuminationFraction(on: candidate)

            if illumination > bestIllumination {
                bestIllumination = illumination
                bestDate = candidate
            }
        }

        let refinedDate = refinedFullMoon(near: bestDate, window: sampleStep)
        guard refinedDate >= date else {
            return nextFullMoon(after: date.addingTimeInterval(sampleStep))
        }

        return refinedDate
    }

    private static func previousFullMoon(before date: Date) -> Date {
        let sampleStep = 6.0 * 60 * 60
        let sampleCount = Int((synodicPeriod * secondsPerDay) / sampleStep)
        var bestDate = date
        var bestIllumination = -Double.infinity

        for sample in 0...sampleCount {
            let candidate = date.addingTimeInterval(-Double(sample) * sampleStep)
            let illumination = illuminationFraction(on: candidate)

            if illumination > bestIllumination {
                bestIllumination = illumination
                bestDate = candidate
            }
        }

        let refinedDate = refinedFullMoon(near: bestDate, window: sampleStep)
        guard refinedDate <= date else {
            return previousFullMoon(before: date.addingTimeInterval(-sampleStep))
        }

        return refinedDate
    }

    private static func refinedFullMoon(near date: Date, window: TimeInterval) -> Date {
        var lower = date.addingTimeInterval(-window)
        var upper = date.addingTimeInterval(window)

        for _ in 0..<28 {
            let span = upper.timeIntervalSince(lower)
            let first = lower.addingTimeInterval(span / 3)
            let second = upper.addingTimeInterval(-span / 3)

            if illuminationFraction(on: first) < illuminationFraction(on: second) {
                lower = first
            } else {
                upper = second
            }
        }

        return lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
    }

    private static func illuminationFraction(on date: Date) -> Double {
        let elongation = lunarElongation(on: date)
        return (1 - cos(elongation.degreesToRadians)) / 2
    }

    private static func lunarElongation(on date: Date) -> Double {
        (moonLongitude(on: date) - sunLongitude(on: date)).normalizedDegrees
    }

    private static func daysSinceJ2000(on date: Date) -> Double {
        date.timeIntervalSince1970 / secondsPerDay + 2_440_587.5 - j2000
    }

    private static func sunLongitude(on date: Date) -> Double {
        let days = daysSinceJ2000(on: date)
        let meanLongitude = (280.46646 + 0.98564736 * days).normalizedDegrees
        let meanAnomaly = (357.52911 + 0.98560028 * days).normalizedDegrees
        let equationOfCenter = 1.914602 * sin(meanAnomaly.degreesToRadians)
            + 0.019993 * sin((2 * meanAnomaly).degreesToRadians)
            + 0.000289 * sin((3 * meanAnomaly).degreesToRadians)

        return (meanLongitude + equationOfCenter).normalizedDegrees
    }

    private static func moonLongitude(on date: Date) -> Double {
        let days = daysSinceJ2000(on: date)
        let meanLongitude = (218.316 + 13.176396 * days).normalizedDegrees
        let meanAnomaly = (134.963 + 13.064993 * days).normalizedDegrees
        let meanElongation = (297.850 + 12.190749 * days).normalizedDegrees
        let argumentOfLatitude = (93.272 + 13.229350 * days).normalizedDegrees

        let correction = 6.289 * sin(meanAnomaly.degreesToRadians)
            + 1.274 * sin((2 * meanElongation - meanAnomaly).degreesToRadians)
            + 0.658 * sin((2 * meanElongation).degreesToRadians)
            + 0.214 * sin((2 * meanAnomaly).degreesToRadians)
            - 0.186 * sin((357.529 + 0.98560028 * days).degreesToRadians)
            - 0.114 * sin((2 * argumentOfLatitude).degreesToRadians)

        return (meanLongitude + correction).normalizedDegrees
    }
}

private extension Double {
    var normalizedDegrees: Double {
        let remainder = truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    var degreesToRadians: Double {
        self * .pi / 180
    }
}

private struct MoonIlluminationMask: Shape {
    let illumination: Double
    let isWaxing: Bool

    func path(in rect: CGRect) -> Path {
        let lit = min(max(illumination, 0), 1)

        if lit <= 0.005 {
            return Path()
        }
        if lit >= 0.9995 {
            return Path(ellipseIn: rect)
        }

        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 36
        let litSide: CGFloat = isWaxing ? 1 : -1
        let terminatorOffset = terminatorOffset(for: lit, radius: radius)
        var path = Path()

        for step in 0...steps {
            let y = center.y - radius + 2 * radius * CGFloat(step) / CGFloat(steps)
            let x = center.x + litSide * circleXOffset(at: y, centerY: center.y, radius: radius)
            let point = CGPoint(x: x, y: y)

            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        for step in stride(from: steps, through: 0, by: -1) {
            let y = center.y - radius + 2 * radius * CGFloat(step) / CGFloat(steps)
            let x = center.x + terminatorOffset * circleXOffset(at: y, centerY: center.y, radius: radius) / radius
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }

    private func circleXOffset(at y: CGFloat, centerY: CGFloat, radius: CGFloat) -> CGFloat {
        let distanceFromCenter = y - centerY
        return sqrt(max(radius * radius - distanceFromCenter * distanceFromCenter, 0))
    }

    private func terminatorOffset(for illumination: Double, radius: CGFloat) -> CGFloat {
        let phaseWidth: CGFloat

        if illumination < 0.5 {
            phaseWidth = CGFloat(1 - 2 * illumination)
        } else {
            phaseWidth = CGFloat(2 * illumination - 1)
        }

        let side: CGFloat
        if illumination < 0.5 {
            side = isWaxing ? 1 : -1
        } else {
            side = isWaxing ? -1 : 1
        }

        return side * phaseWidth * radius
    }

}
