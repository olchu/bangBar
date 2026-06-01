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
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.13))
                    .blur(radius: 8)

                Image("MoonTexture")
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.55), radius: 5, y: 2)
                    .shadow(color: accentColor.opacity(0.2), radius: 10)
            }
            .frame(width: 58, height: 58)

            VStack(spacing: 1) {
                Text(phase.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(phase.fullMoonCountdownText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
        }
        .frame(width: PanelLayout.moonWidgetWidth, height: PanelLayout.nowPlayingWidgetHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phase.name), next full moon \(phase.fullMoonCountdownText)")
    }
}

struct MoonPhase {
    private static let synodicPeriod = 29.53059
    private static let referenceNewMoon: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2000
        components.month = 1
        components.day = 6
        components.hour = 18
        components.minute = 14
        return components.date ?? Date(timeIntervalSince1970: 947182440)
    }()

    private let ageInDays: Double

    init(date: Date) {
        let daysSinceReference = date.timeIntervalSince(Self.referenceNewMoon) / 86_400
        ageInDays = daysSinceReference.positiveRemainder(dividingBy: Self.synodicPeriod)
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

    var fullMoonCountdownText: String {
        if phase == .full {
            return "today"
        }

        let dayCount = max(Int(ceil(daysUntilNextFullMoon)), 1)
        return dayCount == 1 ? "in 1 day" : "in \(dayCount) days"
    }

    private var phase: Phase {
        let normalizedPhase = ageInDays / Self.synodicPeriod
        let index = Int((normalizedPhase * Double(Phase.allCases.count)).rounded()) % Phase.allCases.count
        return Phase.allCases[index]
    }

    private var daysUntilNextFullMoon: Double {
        let fullMoonAge = Self.synodicPeriod / 2
        if ageInDays <= fullMoonAge {
            return fullMoonAge - ageInDays
        }

        return Self.synodicPeriod - ageInDays + fullMoonAge
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
}

private extension Double {
    func positiveRemainder(dividingBy divisor: Double) -> Double {
        let remainder = truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
