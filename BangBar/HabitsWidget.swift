import SwiftUI

struct HabitsWidget: View {
    @ObservedObject var service: HabitService
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex =
        BangBarSettings.defaultAccentColorHex

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if service.habits.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(service.habits) { habit in
                            HabitWidgetRow(
                                habit: habit,
                                isCompleted: service.isCompletedToday(habit),
                                accentColor: accentColor
                            ) {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    service.toggleToday(habit)
                                }
                            }
                        }
                    }
                }
                .scrollClipDisabled(false)
            }
        }
        .frame(
            width: PanelLayout.habitsWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .onAppear {
            service.refreshDay()
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            HStack {
                Text("TODAY")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))

                Spacer()

                Text("\(service.completedTodayCount)/\(service.habits.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.10))

                    Capsule()
                        .fill(accentColor)
                        .frame(width: proxy.size.width * service.todayCompletionRate)
                        .shadow(color: accentColor.opacity(0.35), radius: 3)
                }
            }
            .frame(height: 3)
            .animation(.easeInOut(duration: 0.18), value: service.todayCompletionRate)
        }
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
}

private struct HabitWidgetRow: View {
    let habit: HabitDefinition
    let isCompleted: Bool
    let accentColor: Color
    let action: () -> Void

    private var rowColor: Color {
        isCompleted ? .white.opacity(0.8) : accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(rowColor, lineWidth: 1.4)
                        .frame(width: 14, height: 14)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(rowColor)
                    }
                }

                Text(habit.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(rowColor)
                    .strikethrough(isCompleted, color: rowColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(habit.title)
        .accessibilityLabel(habit.title)
        .accessibilityValue(isCompleted ? "Completed today" : "Not completed today")
        .accessibilityHint("Toggles today's completion")
    }
}
