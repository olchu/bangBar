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
        HStack(alignment: .top, spacing: 16) {
            managementSection
                .frame(width: 310)

            VStack(alignment: .leading, spacing: 18) {
                summarySection
                historySection
                perHabitSection
            }
            .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 10) {
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
                .fixedSize(horizontal: false, vertical: true)
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
        .frame(height: 48)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let sevenDays = service.aggregateCompletionSummary(days: 7)
            let thirtyDays = service.aggregateCompletionSummary(days: 30)

            HStack(spacing: 8) {
                HabitMetricCard(
                    title: "TODAY",
                    value: "\(service.completedTodayCount)/\(service.habits.count)",
                    percentage: percent(service.todayCompletionRate),
                    accentColor: accentColor
                )
                HabitMetricCard(
                    title: "LAST 7 DAYS",
                    value: "\(sevenDays.completedCount)/\(sevenDays.eligibleCount)",
                    percentage: percent(sevenDays.completionRate),
                    accentColor: accentColor
                )
                HabitMetricCard(
                    title: "LAST 30 DAYS",
                    value: "\(thirtyDays.completedCount)/\(thirtyDays.eligibleCount)",
                    percentage: percent(thirtyDays.completionRate),
                    accentColor: accentColor
                )
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("30-day history")
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.secondaryText)

            SettingsCard {
                if service.habits.isEmpty {
                    Text("Add a habit to start building history.")
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                } else {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 15)
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(service.recentDaySummaries()) { summary in
                            HabitHistoryDay(summary: summary, accentColor: accentColor)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var perHabitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                if service.habits.isEmpty {
                    Text("Per-habit streaks will appear here.")
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                } else {
                    VStack(spacing: 0) {
                        HabitStatisticsHeader()
                        SettingsDivider()

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
    @State private var isHovered = false

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
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Delete habit")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(isHovered ? Color.white.opacity(0.045) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
    let percentage: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(SettingsTheme.secondaryText)

            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(SettingsTheme.primaryText)
                .contentTransition(.numericText())

            Text(percentage)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(accentColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
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

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fillColor)
            .aspectRatio(1, contentMode: .fit)
            .help(
                summary.eligibleCount == 0
                    ? "No habits on \(summary.day)"
                    : "\(summary.completedCount) of \(summary.eligibleCount) completed on \(summary.day)"
            )
    }

    private var fillColor: Color {
        guard summary.eligibleCount > 0 else { return .white.opacity(0.05) }
        guard summary.completionRate > 0 else { return .white.opacity(0.13) }
        return accentColor.opacity(0.28 + summary.completionRate * 0.72)
    }
}

private struct HabitStatisticsRow: View {
    let habit: HabitDefinition
    let statistics: HabitStatistics
    let accentColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(habit.title)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(SettingsTheme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(statistics.currentStreak) days")
                .frame(width: 74, alignment: .leading)
            Text("\(statistics.bestStreak) days")
                .frame(width: 68, alignment: .leading)
            completion
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundStyle(SettingsTheme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var completion: some View {
        HStack(spacing: 7) {
            Text("\(Int((statistics.thirtyDayRate * 100).rounded()))%")
                .frame(width: 30, alignment: .trailing)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(accentColor)
                        .frame(width: proxy.size.width * statistics.thirtyDayRate)
                }
            }
            .frame(height: 2)
        }
        .frame(width: 116)
    }
}

private struct HabitStatisticsHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Habit")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Current streak")
                .frame(width: 74, alignment: .leading)
            Text("Best streak")
                .frame(width: 68, alignment: .leading)
            Text("30-day completion")
                .frame(width: 116, alignment: .leading)
        }
        .font(.system(size: 8, weight: .medium, design: .rounded))
        .foregroundStyle(SettingsTheme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 34)
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
