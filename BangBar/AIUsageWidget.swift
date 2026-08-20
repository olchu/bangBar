import SwiftUI

struct AIUsageWidget: View {
    @ObservedObject var service: AIUsageService
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text("AI Usage")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(height: 14)

            if rows.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        AIUsageProviderRow(row: row, accentColor: accentColor)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: PanelLayout.aiUsageWidgetWidth, height: PanelLayout.nowPlayingWidgetHeight, alignment: .topLeading)
        .task {
            while !Task.isCancelled {
                let needsRetry = await service.refresh()
                let interval = needsRetry ? AIUsageService.retryInterval : AIUsageService.refreshInterval

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    private var accentColor: Color { Color(hex: accentColorHex) }

    private var rows: [AIUsageProviderRow.Data] {
        [
            service.codex.map {
                AIUsageProviderRow.Data(name: "Codex", usage: $0, resetDisplay: .providerHeader)
            },
            service.claude.map {
                AIUsageProviderRow.Data(name: "Claude", usage: $0, resetDisplay: .usageRows)
            }
        ]
        .compactMap { $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(accentColor.opacity(0.72))

            Text("Sign in with codex or claude in Terminal")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AIUsageProviderRow: View {
    enum ResetDisplay {
        case providerHeader
        case usageRows
    }

    struct Data: Identifiable {
        let name: String
        let usage: AIProviderUsage
        let resetDisplay: ResetDisplay
        var id: String { name }
    }

    let row: Data
    let accentColor: Color

    private var nextReset: Date? {
        [row.usage.primary?.resetsAt, row.usage.secondary?.resetsAt]
            .compactMap { $0 }
            .min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(row.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer()

                headerResets
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }

            if let primary = row.usage.primary {
                AIUsageBar(
                    window: primary,
                    showsReset: row.resetDisplay == .usageRows,
                    accentColor: accentColor
                )
            }

            if let secondary = row.usage.secondary {
                AIUsageBar(
                    window: secondary,
                    showsReset: row.resetDisplay == .usageRows,
                    accentColor: accentColor
                )
            }
        }
    }

    @ViewBuilder
    private var headerResets: some View {
        switch row.resetDisplay {
        case .providerHeader:
            if let nextReset {
                AIUsageResetBadge(date: nextReset)
            }
        case .usageRows:
            EmptyView()
        }
    }
}

private struct AIUsageResetBadge: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 8, weight: .semibold))

            Text(AIUsageResetFormatter.label(until: date).dropFirst())
                .font(.system(size: 9, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.52))
    }
}

private struct AIUsageBar: View {
    let window: AIUsageWindow
    let showsReset: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(window.label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))

                    Capsule()
                        .fill(barColor)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(width: showsReset ? 75 : nil, height: 5)

            if showsReset {
                Spacer(minLength: 0)

                if let resetsAt = window.resetsAt {
                    AIUsageResetBadge(date: resetsAt)
                        .frame(width: 34, alignment: .leading)
                }
            }

            Text("\(window.usedPercent)%")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(barColor.opacity(0.9))
                .frame(width: 25, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(window.usedPercent, 0), 100)) / 100
    }

    private var barColor: Color {
        if window.usedPercent >= 90 { return accentColor }
        if window.usedPercent < 50 { return .green }
        return .orange
    }
}

/// Shortest single-unit countdown to when a usage window unlocks, e.g. "·3d", "·14h", "·22m".
private enum AIUsageResetFormatter {
    static func label(until date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 60 else { return "·now" }

        let days = Int(seconds / 86400)
        if days > 0 { return "·\(days)d" }
        let hours = Int(seconds / 3600)
        if hours > 0 { return "·\(hours)h" }
        return "·\(Int(seconds / 60))m"
    }
}
