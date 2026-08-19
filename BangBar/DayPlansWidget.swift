import SwiftUI

struct DayPlansWidget: View {
    @ObservedObject var service: DayPlanService

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    private var accentColor: Color { Color(hex: accentColorHex) }

    private let maxVisible = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if service.todaysItems.isEmpty {
                emptyState
            } else {
                activeContent
            }
        }
        .frame(
            width: PanelLayout.dayPlansWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .onAppear {
            service.refreshDay()
            service.reload()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))

            if !service.todaysItems.isEmpty {
                Text("\(service.todaysItems.count) today")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()
        }
    }

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(service.todaysItems.prefix(maxVisible)) { item in
                HStack(spacing: 7) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)

                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if service.todaysItems.count > maxVisible {
                Text("+\(service.todaysItems.count - maxVisible) more")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            Text("No plans today")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
