import SwiftUI
import UniformTypeIdentifiers

struct HabitSettingsContent: View {
    @ObservedObject var service: HabitService
    let accentColor: Color

    @State private var newHabitTitle = ""
    @State private var draggedHabit: HabitDefinition?
    @State private var habitPendingDeletion: HabitDefinition?
    @FocusState private var isNewHabitFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            managementSection
            summarySection
            historySection
            perHabitSection
        }
        .confirmationDialog(
            "Delete this habit and its history?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: habitPendingDeletion
        ) { habit in
            Button("Delete \(habit.title)", role: .destructive) {
                service.deleteHabit(habit)
                habitPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                habitPendingDeletion = nil
            }
        } message: { _ in
            Text("All retained completion history for this habit will also be removed.")
        }
        .onAppear {
            service.refreshDay()
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionLabel("DAILY HABITS")

            SettingsCard {
                VStack(spacing: 0) {
                    addHabitRow

                    if !service.habits.isEmpty {
                        SettingsDivider()

                        ForEach(Array(service.habits.enumerated()), id: \.element.id) { index, habit in
                            EditableHabitRow(
                                habit: habit,
                                accentColor: accentColor,
                                onRename: { service.renameHabit(habit, title: $0) },
                                onDelete: { habitPendingDeletion = habit }
                            )
                            .onDrag {
                                draggedHabit = habit
                                return NSItemProvider(object: habit.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: HabitDropDelegate(
                                    target: habit,
                                    draggedHabit: $draggedHabit,
                                    onMove: service.moveHabit
                                )
                            )

                            if index < service.habits.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }

            Text("Edit names in place. Drag a row to change the order used by the widget.")
                .font(SettingsTheme.captionFont)
                .foregroundStyle(SettingsTheme.secondaryText)
        }
    }

    private var addHabitRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentColor)

            TextField("New daily habit", text: $newHabitTitle)
                .textFieldStyle(.plain)
                .font(SettingsTheme.rowFont)
                .focused($isNewHabitFieldFocused)
                .onSubmit(addHabit)

            Button("Add", action: commitNewHabitAfterEditing)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(canAddHabit ? Color.white : SettingsTheme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(canAddHabit ? accentColor : Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionLabel("OVERVIEW")

            HStack(spacing: 12) {
                HabitMetricCard(
                    title: "TODAY",
                    value: "\(service.completedTodayCount)/\(service.habits.count)",
                    subtitle: percent(service.todayCompletionRate),
                    accentColor: accentColor
                )
                HabitMetricCard(
                    title: "LAST 7 DAYS",
                    value: percent(service.aggregateCompletionRate(days: 7)),
                    subtitle: "completion",
                    accentColor: accentColor
                )
                HabitMetricCard(
                    title: "LAST 30 DAYS",
                    value: percent(service.aggregateCompletionRate(days: 30)),
                    subtitle: "completion",
                    accentColor: accentColor
                )
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionLabel("LAST 30 DAYS")

            SettingsCard {
                if service.habits.isEmpty {
                    Text("Add a habit to start building history.")
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                } else {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 10)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(service.recentDaySummaries()) { summary in
                            HabitHistoryDay(summary: summary, accentColor: accentColor)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var perHabitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionLabel("BY HABIT")

            SettingsCard {
                if service.habits.isEmpty {
                    Text("Per-habit streaks will appear here.")
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.habits.enumerated()), id: \.element.id) { index, habit in
                            HabitStatisticsRow(
                                habit: habit,
                                statistics: service.statistics(for: habit),
                                accentColor: accentColor
                            )

                            if index < service.habits.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var canAddHabit: Bool {
        !newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { habitPendingDeletion != nil },
            set: { if !$0 { habitPendingDeletion = nil } }
        )
    }

    private func addHabit() {
        guard service.addHabit(title: newHabitTitle) != nil else { return }
        newHabitTitle = ""
        isNewHabitFieldFocused = true
    }

    private func commitNewHabitAfterEditing() {
        isNewHabitFieldFocused = false
        Task { @MainActor in
            await Task.yield()
            addHabit()
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct EditableHabitRow: View {
    let habit: HabitDefinition
    let accentColor: Color
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var title: String

    init(
        habit: HabitDefinition,
        accentColor: Color,
        onRename: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.habit = habit
        self.accentColor = accentColor
        self.onRename = onRename
        self.onDelete = onDelete
        _title = State(initialValue: habit.title)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsTheme.secondaryText)
                .frame(width: 18)

            TextField("Habit name", text: $title)
                .textFieldStyle(.plain)
                .font(SettingsTheme.rowFont)
                .onSubmit(commitRename)
                .onChange(of: habit.title) { _, newValue in
                    if title != newValue { title = newValue }
                }
                .onChange(of: title) { _, newValue in
                    if newValue.count > 80 {
                        title = String(newValue.prefix(80))
                    }
                }

            Button {
                commitRename()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Save name")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Delete habit")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func commitRename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            title = habit.title
        } else {
            title = String(trimmed.prefix(80))
            onRename(title)
        }
    }
}

private struct HabitMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettingsTheme.secondaryText)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .contentTransition(.numericText())

            Text(subtitle)
                .font(SettingsTheme.captionFont)
                .foregroundStyle(SettingsTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SettingsTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SettingsTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct HabitHistoryDay: View {
    let summary: HabitDaySummary
    let accentColor: Color

    private var dateLabel: String {
        summary.date.formatted(.dateTime.day())
    }

    private var weekdayLabel: String {
        summary.date.formatted(.dateTime.weekday(.narrow))
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(weekdayLabel)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(SettingsTheme.secondaryText)

            ZStack {
                Circle()
                    .fill(
                        summary.eligibleCount == 0
                            ? Color.white.opacity(0.04)
                            : accentColor.opacity(0.12 + summary.completionRate * 0.88)
                    )
                    .frame(width: 27, height: 27)

                Text(dateLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        summary.completionRate > 0.55
                            ? Color.white
                            : SettingsTheme.secondaryText
                    )
            }
        }
        .help(
            summary.eligibleCount == 0
                ? "No habits on \(summary.day)"
                : "\(summary.completedCount) of \(summary.eligibleCount) completed on \(summary.day)"
        )
    }
}

private struct HabitStatisticsRow: View {
    let habit: HabitDefinition
    let statistics: HabitStatistics
    let accentColor: Color

    var body: some View {
        HStack(spacing: 16) {
            Text(habit.title)
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)
                .lineLimit(1)

            Spacer()

            statistic(value: "\(statistics.currentStreak)d", label: "CURRENT")
            statistic(value: "\(statistics.bestStreak)d", label: "BEST")
            statistic(
                value: "\(Int((statistics.thirtyDayRate * 100).rounded()))%",
                label: "30 DAYS"
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private func statistic(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)

            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettingsTheme.secondaryText)
        }
        .frame(width: 70, alignment: .trailing)
    }
}

private struct HabitDropDelegate: DropDelegate {
    let target: HabitDefinition
    @Binding var draggedHabit: HabitDefinition?
    let onMove: (HabitDefinition, HabitDefinition) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedHabit, draggedHabit.id != target.id else { return }
        onMove(draggedHabit, target)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedHabit = nil
        return true
    }
}
