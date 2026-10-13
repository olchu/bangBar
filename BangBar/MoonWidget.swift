import CoreLocation
import Foundation
import SwiftUI

struct MoonWidget: View {
    private static let infoOverlayVerticalOutset: CGFloat = 0
    private static let moonDiskSize: CGFloat = 78

    let date: Date
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @AppStorage(BangBarSettings.Key.moonUsesCurrentLocation) private var usesCurrentLocation = true
    @AppStorage(BangBarSettings.Key.moonLatitude) private var latitude = 41.0082
    @AppStorage(BangBarSettings.Key.moonLongitude) private var longitude = 28.9784
    @AppStorage(BangBarSettings.Key.moonCurrentLatitude) private var currentLatitude: Double?
    @AppStorage(BangBarSettings.Key.moonCurrentLongitude) private var currentLongitude: Double?
    @ObservedObject private var locationService = MoonLocationService.shared

    private var observerCoordinates: (latitude: Double, longitude: Double) {
        if usesCurrentLocation,
           locationService.authorizationStatus == .authorizedAlways,
           let currentLatitude, let currentLongitude {
            return (currentLatitude, currentLongitude)
        }
        return (latitude, longitude)
    }

    private var phase: MoonPhase {
        MoonPhase(date: date)
    }

    private var accentColor: Color {
        Color(hex: accentColorHex)
    }

    var body: some View {
        ZStack {
            moonDisk
            moonInfoOverlay
        }
        .frame(width: PanelLayout.moonWidgetWidth, height: PanelLayout.nowPlayingWidgetHeight)
        .onAppear {
            if usesCurrentLocation { locationService.requestCurrentLocation() }
        }
        .onChange(of: usesCurrentLocation) { _, enabled in
            if enabled { locationService.requestCurrentLocation() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(phase.name), \(phase.illuminationPercent)% visible, "
                + "next new moon \(phase.newMoonDateText), "
                + "next full moon \(phase.fullMoonDateText)"
        )
    }

    private var moonInfoOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                cornerMetric(
                    label: "ILLUM.",
                    value: "\(phase.illuminationPercent)%",
                    alignment: .leading
                )
                .frame(width: 42, alignment: .leading)

                Spacer(minLength: 0)

                cornerMetric(
                    label: "PHASE",
                    value: phase.shortName,
                    alignment: .trailing,
                    usesAccentColor: false
                )
                    .frame(width: 46, alignment: .trailing)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 8) {
                moonEventMetric(
                    label: "NEW",
                    value: phase.newMoonDateText,
                    alignment: .leading
                )
                    .frame(width: 46, alignment: .leading)

                Spacer(minLength: 0)

                moonEventMetric(
                    label: "FULL",
                    value: phase.fullMoonDateText,
                    alignment: .trailing
                )
                    .frame(width: 46, alignment: .trailing)
            }
        }
        .frame(
            width: PanelLayout.moonWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight + Self.infoOverlayVerticalOutset * 2
        )
        .allowsHitTesting(false)
    }

    private func cornerMetric(
        label: String,
        value: String,
        alignment: HorizontalAlignment,
        showsDot: Bool = false,
        usesAccentColor: Bool = true
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 4) {
                if showsDot {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 4, height: 4)
                }

                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        usesAccentColor ? accentColor.opacity(0.95) : .white.opacity(0.95)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)

            Text(label)
                .font(.system(size: 5.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .tracking(1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func moonEventMetric(
        label: String,
        value: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 5.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .tracking(1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(value)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    private var moonDisk: some View {
        ZStack {
            Image("MoonTexture")
                .resizable()
                .scaledToFill()
                .frame(width: Self.moonDiskSize, height: Self.moonDiskSize)
                .saturation(0.48)
                .brightness(-0.65)

            Image("MoonTexture")
                .resizable()
                .scaledToFill()
                .frame(width: Self.moonDiskSize, height: Self.moonDiskSize)
                .saturation(0.42)
                .contrast(0.86)
                .brightness(-0.12)
                .opacity(0.92)
                .mask {
                    MoonIlluminationMask(
                        illumination: phase.illuminationFraction
                    )
                    .rotation(.degrees(MoonOrientation.brightLimbRotation(
                        date: date,
                        latitude: observerCoordinates.latitude,
                        longitude: observerCoordinates.longitude
                    )))
                }
        }
        .frame(width: Self.moonDiskSize, height: Self.moonDiskSize)
        .clipShape(Circle())
        .offset(y: 3)
        .shadow(color: .black.opacity(0.30), radius: 7, y: 2)
        .shadow(color: accentColor.opacity(0.16), radius: 14)
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

    var shortName: String {
        switch phase {
        case .new:
            return "New"
        case .waxingCrescent:
            return "Waxing"
        case .firstQuarter:
            return "First"
        case .waxingGibbous:
            return "Waxing"
        case .full:
            return "Full"
        case .waningGibbous:
            return "Waning"
        case .lastQuarter:
            return "Last"
        case .waningCrescent:
            return "Waning"
        }
    }

    var illuminationPercent: Int {
        Int((illuminationFraction * 100).rounded())
    }

    var fullMoonDateText: String {
        Self.fullMoonDateFormatter.string(from: nextFullMoonDate)
    }

    var newMoonDateText: String {
        Self.fullMoonDateFormatter.string(from: nextNewMoonDate)
    }

    var illuminationFraction: Double {
        (1 - cos(elongation.degreesToRadians)) / 2
    }

    private var phase: Phase {
        let index = Int((elongation / 45).rounded()) % Phase.allCases.count
        return Phase.allCases[index]
    }

    private var nextFullMoonDate: Date {
        Self.nextFullMoon(after: date)
    }

    private var nextNewMoonDate: Date {
        Self.nextNewMoon(after: date)
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

    private static func nextNewMoon(after date: Date) -> Date {
        let sampleStep = 6.0 * 60 * 60
        let sampleCount = Int((synodicPeriod * secondsPerDay) / sampleStep)
        var bestDate = date
        var bestIllumination = Double.infinity

        for sample in 0...sampleCount {
            let candidate = date.addingTimeInterval(Double(sample) * sampleStep)
            let illumination = illuminationFraction(on: candidate)

            if illumination < bestIllumination {
                bestIllumination = illumination
                bestDate = candidate
            }
        }

        let refinedDate = refinedNewMoon(near: bestDate, window: sampleStep)
        guard refinedDate >= date else {
            return nextNewMoon(after: date.addingTimeInterval(sampleStep))
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

    private static func refinedNewMoon(near date: Date, window: TimeInterval) -> Date {
        var lower = date.addingTimeInterval(-window)
        var upper = date.addingTimeInterval(window)

        for _ in 0..<28 {
            let span = upper.timeIntervalSince(lower)
            let first = lower.addingTimeInterval(span / 3)
            let second = upper.addingTimeInterval(-span / 3)

            if illuminationFraction(on: first) > illuminationFraction(on: second) {
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
