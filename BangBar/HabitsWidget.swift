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
                                    .background { ScrollElasticityDisabler() }
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
        let dates = recentDates
        return VStack(spacing: 1) {
            ForEach(service.habits) { habit in
                HabitWidgetRow(
                    habit: habit,
                    dates: dates,
                    dayStates: dates.map { service.dayState(for: habit, on: $0) },
                    isCompleted: service.isCompletedToday(habit),
                    currentStreak: service.currentStreak(for: habit),
                    accentColor: accentColor,
                    isPanelContentVisible: isPanelContentVisible,
                    onToggleDay: { toggle(habit, on: $0) }
                )
            }
        }
        .padding(.top, 2)
    }

    private var header: some View {
        let isAllDone = !service.habits.isEmpty
            && service.completedTodayCount == service.habits.count

        return HStack(spacing: 6) {
            Image(systemName: isAllDone ? "checkmark.seal.fill" : "checklist")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accentColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 14, height: 16)

            if !service.habits.isEmpty {
                Text(isAllDone ? "All done" : "\(service.completedTodayCount)/\(service.habits.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()

                TodayProgressSegments(
                    total: service.habits.count,
                    completed: service.completedTodayCount,
                    accentColor: accentColor
                )
                .padding(.leading, 2)
            }
        }
        .frame(height: 16)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: service.completedTodayCount)
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

    private var recentDates: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private func toggle(_ habit: HabitDefinition, on date: Date) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            service.toggle(habit, on: date)
        }
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

// Rubber-banding in these short clipped lists reads as a jolt at the edges, and SwiftUI has no modifier to turn it off.
struct ScrollElasticityDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollElasticityDisablerView {
        ScrollElasticityDisablerView()
    }

    func updateNSView(_ nsView: ScrollElasticityDisablerView, context: Context) {
        nsView.disableElasticity()
    }
}

final class ScrollElasticityDisablerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disableElasticity()
        DispatchQueue.main.async { [weak self] in
            self?.disableElasticity()
        }
    }

    func disableElasticity() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
    }
}

private struct TodayProgressSegments: View {
    let total: Int
    let completed: Int
    let accentColor: Color

    var body: some View {
        HStack(spacing: total > 10 ? 1 : 2) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < completed ? accentColor : Color.white.opacity(0.14))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 3)
    }
}

private struct HabitWidgetRow: View {
    let habit: HabitDefinition
    let dates: [Date]
    let dayStates: [HabitDayState]
    let isCompleted: Bool
    let currentStreak: Int
    let accentColor: Color
    let isPanelContentVisible: Bool
    let onToggleDay: (Date) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if let today = dates.last { onToggleDay(today) }
            } label: {
                HStack(spacing: 6) {
                    HabitCheckbox(isCompleted: isCompleted, accentColor: accentColor)

                    Text(habit.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(isCompleted ? 0.42 : 0.9))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(habit.title)
            .accessibilityLabel(habit.title)
            .accessibilityValue(isCompleted ? "Completed today" : "Not completed today")
            .accessibilityHint("Toggles today's completion")

            HStack(spacing: 0) {
                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    HabitWidgetDayCell(
                        date: date,
                        state: dayStates[index],
                        isToday: index == dates.count - 1,
                        accentColor: accentColor,
                        isPanelContentVisible: isPanelContentVisible
                    ) {
                        onToggleDay(date)
                    }
                }
            }

            streakBadge
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.05 : 0))
        )
        .onHover { isHovered = $0 }
    }

    private var streakBadge: some View {
        // An outlined flame marks a streak that today's check-in has not extended yet.
        HStack(spacing: 2) {
            if currentStreak > 0 {
                Image(systemName: isCompleted ? "flame.fill" : "flame")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isCompleted ? accentColor : .white.opacity(0.42))
            }

            Text(currentStreak > 0 ? "\(currentStreak)" : "–")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(isCompleted && currentStreak > 0 ? 0.85 : 0.42))
                .contentTransition(.numericText())
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering, isPanelContentVisible else {
                TooltipManager.shared.hide()
                return
            }
            TooltipManager.shared.show(text: streakTooltip)
        }
    }

    private var streakTooltip: String {
        guard currentStreak > 0 else { return "No streak yet" }
        let days = currentStreak == 1 ? "1 day" : "\(currentStreak) days"
        return isCompleted ? "\(days) streak" : "\(days) streak · check in today to keep it"
    }
}

private struct HabitCheckbox: View {
    let isCompleted: Bool
    let accentColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(accentColor.opacity(isCompleted ? 0 : 1), lineWidth: 1.25)

            Circle()
                .fill(accentColor)
                .scaleEffect(isCompleted ? 1 : 0.2)
                .opacity(isCompleted ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.black)
                .scaleEffect(isCompleted ? 1 : 0.4)
                .opacity(isCompleted ? 1 : 0)
        }
        .frame(width: 14, height: 14)
    }
}

private struct HabitWidgetDayCell: View {
    let date: Date
    let state: HabitDayState
    let isToday: Bool
    let accentColor: Color
    let isPanelContentVisible: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(fillColor)
                .overlay {
                    if isToday, state != .complete {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.85), lineWidth: 1)
                    }
                }
                .frame(width: 7, height: 7)
                .scaleEffect(isHovered ? 1.3 : 1)
                .frame(width: 9.5, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            guard hovering, isPanelContentVisible else {
                TooltipManager.shared.hide()
                return
            }
            TooltipManager.shared.show(text: tooltip)
        }
        .accessibilityLabel(tooltip)
    }

    private var fillColor: Color {
        switch state {
        case .complete: accentColor
        case .incomplete: .white.opacity(isHovered ? 0.3 : 0.16)
        case .ineligible: .white.opacity(isHovered ? 0.16 : 0.06)
        }
    }

    private var tooltip: String {
        let dateText = isToday ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day())
        return switch state {
        case .complete: "\(dateText) · done"
        case .incomplete: "\(dateText) · not done"
        case .ineligible: "\(dateText) · before start"
        }
    }
}
