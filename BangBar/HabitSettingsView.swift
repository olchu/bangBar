import SwiftUI
import UniformTypeIdentifiers

private enum TrackerLayout {
    static let handleWidth: CGFloat = 12
    static let nameMinWidth: CGFloat = 150
    static let cellSize: CGFloat = 18
    static let cellSpacing: CGFloat = 4
    static let streakWidth: CGFloat = 56
    static let rateWidth: CGFloat = 44
    static let actionWidth: CGFloat = 22
    static let columnSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 36
    static let smallFont = Font.system(size: 11, weight: .medium, design: .monospaced)

    static func dayCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 14 }
        let fixed = cardPadding + handleWidth + nameMinWidth + streakWidth + rateWidth
            + actionWidth + columnSpacing * 5
        let count = Int((width - fixed + cellSpacing) / (cellSize + cellSpacing))
        return min(max(count, 7), 21)
    }
}

struct HabitSettingsContent: View {
    @ObservedObject var service: HabitService
    let accentColor: Color

    @State private var draggedHabit: HabitDefinition?
    @State private var habitPendingDeletion: HabitDefinition?
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        let statistics = Dictionary(
            uniqueKeysWithValues: service.habits.map { ($0.id, service.statistics(for: $0)) }
        )

        VStack(alignment: .leading, spacing: 24) {
            if !service.habits.isEmpty {
                summaryStrip(statistics: statistics)
            }

            trackerSection(statistics: statistics)

            if !service.habits.isEmpty {
                activitySection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
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

    private func summaryStrip(statistics: [UUID: HabitStatistics]) -> some View {
        let week = service.aggregateCompletionSummary(days: 7)
        let month = service.aggregateCompletionSummary(days: 30)
        let remaining = service.habits.count - service.completedTodayCount
        let bestHabit = service.habits.max {
            (statistics[$0.id]?.bestStreak ?? 0) < (statistics[$1.id]?.bestStreak ?? 0)
        }
        let bestStreak = bestHabit.flatMap { statistics[$0.id]?.bestStreak } ?? 0

        return SettingsCard {
            HStack(alignment: .top, spacing: 18) {
                HabitMetric(
                    title: "TODAY",
                    value: "\(service.completedTodayCount)/\(service.habits.count)",
                    detail: remaining == 0 ? "All done" : "\(remaining) left",
                    progress: service.todayCompletionRate,
                    accentColor: accentColor
                )
                MetricDivider()
                HabitMetric(
                    title: "7 DAYS",
                    value: percent(week.completionRate),
                    detail: "\(week.completedCount) of \(week.eligibleCount) check-ins",
                    progress: week.completionRate,
                    accentColor: accentColor
                )
                MetricDivider()
                HabitMetric(
                    title: "30 DAYS",
                    value: percent(month.completionRate),
                    detail: "\(month.completedCount) of \(month.eligibleCount) check-ins",
                    progress: month.completionRate,
                    accentColor: accentColor
                )
                MetricDivider()
                HabitMetric(
                    title: "BEST STREAK",
                    value: "\(bestStreak)d",
                    detail: bestStreak > 0 ? bestHabit?.title ?? "" : "No streak yet",
                    progress: nil,
                    accentColor: accentColor
                )
            }
        }
    }

    private func trackerSection(statistics: [UUID: HabitStatistics]) -> some View {
        let dates = trackerDates(count: TrackerLayout.dayCount(for: contentWidth))

        return VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("TRACKER")

            SettingsCard {
                VStack(spacing: 0) {
                    if !service.habits.isEmpty {
                        TrackerHeader(dates: dates, accentColor: accentColor)
                        SettingsDivider()

                        ForEach(service.habits) { habit in
                            HabitTrackerRow(
                                service: service,
                                habit: habit,
                                dates: dates,
                                statistics: statistics[habit.id],
                                accentColor: accentColor,
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

                            SettingsDivider()
                        }
                    }

                    NewHabitRow(accentColor: accentColor) { title in
                        service.addHabit(title: title) != nil
                    }
                }
            }

            Text(
                service.habits.isEmpty
                    ? "Add your first habit. It will appear in the panel widget."
                    : "Click any day to mark it, including past days. Drag a row to reorder the widget."
            )
            .font(SettingsTheme.descriptionFont)
            .foregroundStyle(SettingsTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SettingsSectionLabel("ACTIVITY")
                Spacer()
                ActivityLegend(accentColor: accentColor)
            }

            SettingsCard {
                HabitActivityHeatmap(
                    service: service,
                    accentColor: accentColor,
                    availableWidth: contentWidth
                )
                .padding(.vertical, 16)
            }
        }
    }

    private func trackerDates(count: Int) -> [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { habitPendingDeletion != nil },
            set: { if !$0 { habitPendingDeletion = nil } }
        )
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct HabitMetric: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double?
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TrackerLayout.smallFont)
                .foregroundStyle(SettingsTheme.secondaryText)

            Text(value)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundStyle(SettingsTheme.primaryText)
                .contentTransition(.numericText())

            Text(detail)
                .font(TrackerLayout.smallFont)
                .foregroundStyle(SettingsTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            if let progress {
                ProgressLine(progress: progress, accentColor: accentColor)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

private struct MetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsTheme.border)
            .frame(width: 1)
            .padding(.vertical, 16)
    }
}

private struct ProgressLine: View {
    let progress: Double
    let accentColor: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(accentColor)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

private struct TrackerHeader: View {
    let dates: [Date]
    let accentColor: Color

    var body: some View {
        HStack(spacing: TrackerLayout.columnSpacing) {
            Color.clear.frame(width: TrackerLayout.handleWidth, height: 1)

            Text("HABIT")
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: TrackerLayout.cellSpacing) {
                ForEach(dates, id: \.self) { date in
                    let isToday = Calendar.autoupdatingCurrent.isDateInToday(date)
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .opacity(0.6)
                        Text(date.formatted(.dateTime.day()))
                    }
                    .foregroundStyle(isToday ? accentColor : SettingsTheme.secondaryText)
                    .frame(width: TrackerLayout.cellSize)
                }
            }

            Text("STREAK")
                .frame(width: TrackerLayout.streakWidth, alignment: .trailing)
            Text("30D")
                .frame(width: TrackerLayout.rateWidth, alignment: .trailing)
            Color.clear.frame(width: TrackerLayout.actionWidth, height: 1)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(SettingsTheme.secondaryText)
        .padding(.vertical, 12)
    }
}

private struct HabitTrackerRow: View {
    @ObservedObject var service: HabitService
    let habit: HabitDefinition
    let dates: [Date]
    let statistics: HabitStatistics?
    let accentColor: Color
    let onDelete: () -> Void

    @State private var title: String
    @State private var isHovered = false
    @FocusState private var isNameFocused: Bool

    init(
        service: HabitService,
        habit: HabitDefinition,
        dates: [Date],
        statistics: HabitStatistics?,
        accentColor: Color,
        onDelete: @escaping () -> Void
    ) {
        self.service = service
        self.habit = habit
        self.dates = dates
        self.statistics = statistics
        self.accentColor = accentColor
        self.onDelete = onDelete
        _title = State(initialValue: habit.title)
    }

    var body: some View {
        HStack(spacing: TrackerLayout.columnSpacing) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SettingsTheme.secondaryText)
                .opacity(isHovered ? 1 : 0)
                .frame(width: TrackerLayout.handleWidth)

            nameField

            HStack(spacing: TrackerLayout.cellSpacing) {
                ForEach(dates, id: \.self) { date in
                    HabitDayCell(
                        state: service.dayState(for: habit, on: date),
                        date: date,
                        accentColor: accentColor
                    ) {
                        withAnimation(.easeOut(duration: 0.12)) {
                            service.toggle(habit, on: date)
                        }
                    }
                }
            }

            streakLabel
                .frame(width: TrackerLayout.streakWidth, alignment: .trailing)

            Text("\(Int(((statistics?.thirtyDayRate ?? 0) * 100).rounded()))%")
                .frame(width: TrackerLayout.rateWidth, alignment: .trailing)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: TrackerLayout.actionWidth, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .help("Delete habit")
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(SettingsTheme.secondaryText)
        .frame(height: 46)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Delete Habit…", role: .destructive, action: onDelete)
        }
    }

    private var nameField: some View {
        TextField("Habit name", text: $title)
            .textFieldStyle(.plain)
            .font(SettingsTheme.rowFont)
            .foregroundStyle(SettingsTheme.primaryText)
            .lineLimit(1)
            .focused($isNameFocused)
            .onSubmit(commitRename)
            .onChange(of: isNameFocused) { _, isFocused in
                if !isFocused { commitRename() }
            }
            .onChange(of: habit.title) { _, newValue in
                if title != newValue { title = newValue }
            }
            .onChange(of: title) { _, newValue in
                if newValue.count > 80 {
                    title = String(newValue.prefix(80))
                }
            }
            .frame(minWidth: TrackerLayout.nameMinWidth, maxWidth: .infinity, alignment: .leading)
    }

    private var streakLabel: some View {
        let streak = statistics?.currentStreak ?? 0
        return HStack(spacing: 4) {
            if streak > 0 {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
            }
            Text("\(streak)d")
                .foregroundStyle(streak > 0 ? SettingsTheme.primaryText : SettingsTheme.secondaryText)
        }
        .help("Current streak · best \(statistics?.bestStreak ?? 0)d")
    }

    private func commitRename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            title = habit.title
        } else if trimmed != habit.title {
            title = String(trimmed.prefix(80))
            service.renameHabit(habit, title: title)
        }
    }
}

private struct HabitDayCell: View {
    let state: HabitDayState
    let date: Date
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(date)

        Button(action: action) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(borderColor(isToday: isToday), lineWidth: 1)
                }
                .frame(width: TrackerLayout.cellSize, height: TrackerLayout.cellSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    private var fillColor: Color {
        switch state {
        case .complete: accentColor.opacity(isHovered ? 0.78 : 1)
        case .incomplete: .white.opacity(isHovered ? 0.18 : 0.08)
        case .ineligible: .white.opacity(isHovered ? 0.1 : 0.02)
        }
    }

    private func borderColor(isToday: Bool) -> Color {
        if isToday { return accentColor.opacity(0.9) }
        return state == .ineligible ? .white.opacity(0.07) : .clear
    }

    private var helpText: String {
        let dateText = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return switch state {
        case .complete: "\(dateText) · Done. Click to undo."
        case .incomplete: "\(dateText) · Not done. Click to mark."
        case .ineligible: "\(dateText) · Before this habit started. Click to backfill."
        }
    }
}

private struct NewHabitRow: View {
    let accentColor: Color
    let onAdd: (String) -> Bool

    @State private var title = ""
    @FocusState private var isFocused: Bool

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: TrackerLayout.columnSpacing) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: TrackerLayout.handleWidth)

            TextField("New habit", text: $title)
                .textFieldStyle(.plain)
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)
                .focused($isFocused)
                .onSubmit(add)
                .onChange(of: title) { _, newValue in
                    if newValue.count > 80 {
                        title = String(newValue.prefix(80))
                    }
                }

            if canAdd {
                Button(action: add) {
                    HStack(spacing: 6) {
                        Text("Add")
                        Image(systemName: "return")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(accentColor))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(height: 48)
        .animation(.easeOut(duration: 0.12), value: canAdd)
    }

    private func add() {
        guard onAdd(title) else { return }
        title = ""
        isFocused = true
    }
}

private struct HabitActivityHeatmap: View {
    @ObservedObject var service: HabitService
    let accentColor: Color
    let availableWidth: CGFloat

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 30

    private struct MonthLabel: Identifiable {
        let column: Int
        let title: String
        var id: Int { column }
    }

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let columns = weekColumns(count: weekCount, today: today, calendar: calendar)

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                ForEach(monthLabels(for: columns, calendar: calendar)) { label in
                    Text(label.title)
                        .offset(x: CGFloat(label.column) * (cellSize + gap))
                }
            }
            .frame(height: 12, alignment: .leading)
            .padding(.leading, labelWidth + gap)

            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(Array((columns.first ?? []).enumerated()), id: \.offset) { row, date in
                        Text(row.isMultiple(of: 2) ? date.formatted(.dateTime.weekday(.abbreviated)) : "")
                            .frame(height: cellSize)
                    }
                }
                .frame(width: labelWidth, alignment: .leading)

                ForEach(columns.indices, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(columns[column], id: \.self) { date in
                            ActivityCell(
                                summary: date > today ? nil : service.daySummary(for: date),
                                accentColor: accentColor,
                                size: cellSize
                            )
                        }
                    }
                }
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(SettingsTheme.secondaryText)
    }

    private var weekCount: Int {
        guard availableWidth > 0 else { return 20 }
        let usable = availableWidth - TrackerLayout.cardPadding - labelWidth - gap
        return min(max(Int((usable + gap) / (cellSize + gap)), 8), 53)
    }

    private func weekColumns(count: Int, today: Date, calendar: Calendar) -> [[Date]] {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let firstWeekStart = calendar.date(
            byAdding: .day,
            value: -(count - 1) * 7,
            to: currentWeekStart
        ) else {
            return []
        }

        return (0..<count).map { column in
            (0..<7).compactMap { row in
                calendar.date(byAdding: .day, value: column * 7 + row, to: firstWeekStart)
            }
        }
    }

    private func monthLabels(for columns: [[Date]], calendar: Calendar) -> [MonthLabel] {
        var labels: [MonthLabel] = []
        for (index, week) in columns.enumerated() {
            let monthStart = week.first { calendar.component(.day, from: $0) == 1 }
            guard let date = monthStart ?? (index == 0 ? week.first : nil) else { continue }
            if let last = labels.last, index - last.column < 3 {
                // The partial first month would collide with the next month's label.
                if last.column == 0 { labels.removeLast() } else { continue }
            }
            labels.append(MonthLabel(column: index, title: date.formatted(.dateTime.month(.abbreviated))))
        }
        return labels
    }
}

private struct ActivityCell: View {
    let summary: HabitDaySummary?
    let accentColor: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(summary.map { ActivityLevel(summary: $0).color(accentColor: accentColor) } ?? .clear)
            .frame(width: size, height: size)
            .help(helpText)
    }

    private var helpText: String {
        guard let summary else { return "" }
        let dateText = summary.date.formatted(.dateTime.day().month(.abbreviated).year())
        guard summary.eligibleCount > 0 else { return "\(dateText) · No habits yet" }
        return "\(dateText) · \(summary.completedCount) of \(summary.eligibleCount) done"
    }
}

private enum ActivityLevel: CaseIterable {
    case none
    case zero
    case low
    case medium
    case high
    case full

    init(summary: HabitDaySummary) {
        guard summary.eligibleCount > 0 else {
            self = .none
            return
        }
        let rate = summary.completionRate
        self = switch rate {
        case 1...: .full
        case 0.66...: .high
        case 0.33...: .medium
        case let value where value > 0: .low
        default: .zero
        }
    }

    func color(accentColor: Color) -> Color {
        switch self {
        case .none: .white.opacity(0.035)
        case .zero: .white.opacity(0.09)
        case .low: accentColor.opacity(0.3)
        case .medium: accentColor.opacity(0.5)
        case .high: accentColor.opacity(0.75)
        case .full: accentColor
        }
    }
}

private struct ActivityLegend: View {
    let accentColor: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("Less")
                .padding(.trailing, 3)
            ForEach([ActivityLevel.zero, .low, .medium, .high, .full], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(level.color(accentColor: accentColor))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .padding(.leading, 3)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(SettingsTheme.secondaryText)
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
