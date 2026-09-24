import AppKit
import SwiftUI

struct HabitsWidget: View {
    @ObservedObject var service: HabitService
    let isPanelContentVisible: Bool
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex =
        BangBarSettings.defaultAccentColorHex
    @State private var scrollViewIdentity = UUID()
    @State private var pendingScrollReset: Task<Void, Never>?
    @State private var pendingScrollEnable: Task<Void, Never>?
    @State private var isScrollEnabled = false

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if service.habits.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    Group {
                        if isScrollEnabled {
                            ScrollView(.vertical, showsIndicators: true) {
                                habitRows
                            }
                            .id(scrollViewIdentity)
                            .scrollClipDisabled(false)
                        } else {
                            habitRows
                        }
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(
            width: PanelLayout.habitsWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .background {
            PanelSwipeExclusionRegion()
        }
        .onAppear {
            service.refreshDay()
        }
        .onChange(of: isPanelContentVisible, initial: true) { _, isVisible in
            pendingScrollReset?.cancel()
            pendingScrollEnable?.cancel()

            if isVisible {
                pendingScrollEnable = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, isPanelContentVisible else { return }

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isScrollEnabled = true
                    }
                }
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isScrollEnabled = false
            }

            pendingScrollReset = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, !isPanelContentVisible else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollViewIdentity = UUID()
                }
            }
        }
        .onDisappear {
            pendingScrollReset?.cancel()
            pendingScrollEnable?.cancel()
        }
    }

    private var habitRows: some View {
        VStack(spacing: 1) {
            ForEach(service.habits) { habit in
                HabitWidgetRow(
                    habit: habit,
                    isCompleted: service.isCompletedToday(habit),
                    recentStates: service.recentStates(for: habit),
                    currentStreak: service.currentStreak(for: habit),
                    accentColor: accentColor
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        service.toggleToday(habit)
                    }
                }
            }
        }
        .padding(.top, 3)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(weekDates, id: \.self) { date in
                        let summary = service.daySummary(for: date)

                        VStack(spacing: 3) {
                            Text(weekdayLabel(for: date))
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.56))

                            WeeklyCompletionDot(
                                summary: summary,
                                isToday: isToday(date),
                                accentColor: accentColor
                            )
                        }
                        .frame(width: 17)
                    }
                }
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: service.todayCompletionRate)
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(service.completedTodayCount)/\(service.habits.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 31, height: 31)
            .animation(.easeInOut(duration: 0.18), value: service.todayCompletionRate)
        }
        .frame(height: 31)
    }

    private var emptyState: some View {
        HStack(spacing: 7) {
            Circle()
                .stroke(accentColor, lineWidth: 1.5)
                .frame(width: 13, height: 13)

            Text("Add habits in Settings")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else {
            return [today]
        }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: monday)
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow)).uppercased()
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.autoupdatingCurrent.isDateInToday(date)
    }

}

struct PanelSwipeExclusionRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelSwipeExclusionView {
        PanelSwipeExclusionView()
    }

    func updateNSView(_ nsView: PanelSwipeExclusionView, context: Context) {}
}

final class PanelSwipeExclusionView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct WeeklyCompletionDot: View {
    let summary: HabitDaySummary
    let isToday: Bool
    let accentColor: Color

    private let size: CGFloat = 7

    private var helpText: String {
        let weekday = summary.date.formatted(.dateTime.weekday(.wide))
        guard summary.eligibleCount > 0 else {
            return "\(weekday) · No habits"
        }
        return "\(weekday) · \(summary.completedCount) of \(summary.eligibleCount)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(.white.opacity(summary.eligibleCount > 0 ? 0.16 : 0.06))

            Rectangle()
                .fill(accentColor)
                .frame(height: size * summary.completionRate)
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(isToday ? accentColor : .clear, lineWidth: 1.2)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.18), value: summary.completionRate)
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

private struct HabitWidgetRow: View {
    let habit: HabitDefinition
    let isCompleted: Bool
    let recentStates: [HabitDayState]
    let currentStreak: Int
    let accentColor: Color
    let action: () -> Void

    private var titleColor: Color {
        isCompleted ? .white.opacity(0.42) : .white.opacity(0.9)
    }

    private var statusColor: Color {
        isCompleted ? .white.opacity(0.58) : accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(statusColor, lineWidth: 1.25)
                        .frame(width: 15, height: 15)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }

                Text(habit.title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(titleColor)
                    .strikethrough(isCompleted, color: titleColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 3) {
                    ForEach(Array(recentStates.enumerated()), id: \.offset) { _, state in
                        Circle()
                            .fill(color(for: state))
                            .frame(width: 5, height: 5)
                    }
                }

                Text("\(currentStreak)d")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(width: 20, alignment: .trailing)
            }
            .padding(.horizontal, 2)
            .frame(height: 19)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(habit.title)
        .accessibilityLabel(habit.title)
        .accessibilityValue(isCompleted ? "Completed today" : "Not completed today")
        .accessibilityHint("Toggles today's completion")
    }

    private func color(for state: HabitDayState) -> Color {
        switch state {
        case .ineligible:
            return .white.opacity(0.06)
        case .incomplete:
            return .white.opacity(0.18)
        case .complete:
            return accentColor
        }
    }
}
