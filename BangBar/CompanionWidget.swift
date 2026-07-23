import SwiftUI

struct CompanionWidget: View {
    @ObservedObject var service: CompanionService
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 5) {
                companion
                Text(service.statusText)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            .frame(width: 72)

            VStack(spacing: 7) {
                meter(label: "FOOD", value: service.state.hunger)
                meter(label: "HAPPY", value: service.state.happiness)
                meter(label: "CLEAN", value: service.state.cleanliness)

                HStack(spacing: 5) {
                    actionButton("fork.knife", help: "Feed", action: service.feed)
                    actionButton("hand.tap", help: "Pet", action: service.pet)
                    actionButton("sparkles", help: "Clean", action: service.clean)
                }
            }
        }
        .frame(width: PanelLayout.companionWidgetWidth, height: PanelLayout.nowPlayingWidgetHeight)
    }

    private var companion: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.95), accentColor.opacity(0.46)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 54, height: 49)
                .overlay(Ellipse().stroke(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: accentColor.opacity(0.28), radius: 8)

            HStack(spacing: 13) {
                Circle().fill(.black.opacity(0.82)).frame(width: 5, height: 7)
                Circle().fill(.black.opacity(0.82)).frame(width: 5, height: 7)
            }
            .offset(y: -4)

            Capsule()
                .fill(.black.opacity(0.62))
                .frame(width: 11, height: 2)
                .offset(y: 10)
        }
        .frame(width: 68, height: 66)
        .overlay(alignment: .top) {
            Capsule()
                .fill(accentColor.opacity(0.9))
                .frame(width: 3, height: 12)
                .rotationEffect(.degrees(-18))
                .offset(y: 2)
        }
        .scaleEffect(service.reaction == nil ? 1 : 1.06)
        .animation(.spring(response: 0.24, dampingFraction: 0.55), value: service.reaction)
    }

    private func meter(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 28, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(0...CompanionRules.meterRange.upperBound, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < value ? accentColor : .white.opacity(0.10))
                        .frame(width: 7, height: 5)
                }
            }
        }
    }

    private func actionButton(_ image: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
