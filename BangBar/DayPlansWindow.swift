import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DayPlansWindowController: NSWindowController {
    static let shared = DayPlansWindowController()

    private let service = DayPlanService.shared

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tasks"
        window.minSize = NSSize(width: 760, height: 500)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: DayPlansWindowView(service: service))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        service.refreshDay()
        service.reload()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct DayPlansWindowView: View {
    @ObservedObject var service: DayPlanService

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var newTaskTitle = ""
    @State private var newTaskGroupID: UUID?
    @State private var selectedGroupFilterID: UUID?
    @State private var selectedFilter = DayPlansTaskFilter.today
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @State private var draggedTaskID: UUID?
    @FocusState private var isNewTaskFocused: Bool

    private var accentColor: Color { Color(hex: accentColorHex) }
    private var calendar: Calendar { .autoupdatingCurrent }
    private var selectedDayID: String {
        DayPlanService.dayIdentifier(for: selectedDate, calendar: calendar)
    }
    private var todaysItems: [DayPlanItem] { service.todaysItems }
    private var selectedDayItems: [DayPlanItem] {
        service.items.filter { $0.date == selectedDayID }
    }
    private var displayedItems: [DayPlanItem] {
        let baseItems: [DayPlanItem] = switch selectedFilter {
        case .today:
            selectedDayItems
        case .all:
            service.items
        case .completed:
            service.items.filter(\.isCompleted)
        }

        guard let selectedGroupFilterID else { return baseItems }
        return baseItems.filter { $0.groupID == selectedGroupFilterID }
    }
    private var activeItems: [DayPlanItem] { displayedItems.filter { !$0.isCompleted } }
    private var completedItems: [DayPlanItem] { displayedItems.filter(\.isCompleted) }
    private var headerTitle: String {
        if selectedFilter == .all { return "All Tasks" }
        if selectedFilter == .completed { return "Completed" }
        if calendar.isDateInToday(selectedDate) { return "Today" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(SettingsTheme.border)
                .frame(width: 1)

            mainContent
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(SettingsTheme.primaryText)
        .background(SettingsTheme.background)
        .containerBackground(SettingsTheme.background, for: .window)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            service.refreshDay()
            service.reload()
            selectedDate = Date()
            displayedMonth = Date()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            titleBarSpacer

            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 20, weight: .semibold))
                Text("Tasks")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(SettingsTheme.primaryText)
            .padding(.horizontal, 28)

            monthCard
                .padding(.horizontal, 28)

            VStack(spacing: 8) {
                sidebarRow(
                    icon: "sun.max",
                    title: "Today",
                    count: todaysItems.count,
                    filter: .today
                ) {
                    selectedFilter = .today
                    selectedDate = Date()
                    displayedMonth = Date()
                }
                sidebarRow(
                    icon: "list.bullet",
                    title: "All Tasks",
                    count: service.items.count,
                    filter: .all
                ) {
                    selectedFilter = .all
                }
                sidebarRow(
                    icon: "checkmark.circle",
                    title: "Completed",
                    count: service.items.filter(\.isCompleted).count,
                    filter: .completed
                ) {
                    selectedFilter = .completed
                }
            }
            .padding(.horizontal, 18)

            Spacer()

            Button(action: focusAddField) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .foregroundStyle(accentColor)
                    Text("Add Task")
                        .foregroundStyle(SettingsTheme.primaryText)
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(SettingsTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(width: 250)
        .background(Color.black.opacity(0.96))
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            titleBarSpacer

            HStack(alignment: .center, spacing: 14) {
                Text(headerTitle)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("\(displayedItems.count)")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentColor)

                Spacer()

                groupFilterDots

                Button(action: addTask) {
                    Label("Add Task", systemImage: "plus")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(accentColor)
                                .shadow(color: accentColor.opacity(0.35), radius: 10)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canAddTask)
                .opacity(canAddTask ? 1 : 0.55)
            }

            VStack(spacing: 28) {
                taskSection(title: "ACTIVE", tasks: activeItems, isCompletedSection: false)
                taskSection(title: "COMPLETED", tasks: completedItems, isCompletedSection: true)
            }

            Spacer()

            bottomBar
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleBarSpacer: some View {
        Color.clear.frame(height: 48)
    }

    private var monthCard: some View {
        let days = calendarDays()

        return VStack(spacing: 18) {
            HStack {
                Button {
                    moveDisplayedMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Spacer()
                Text(monthTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    moveDisplayedMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(SettingsTheme.primaryText.opacity(0.78))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
                ForEach(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(SettingsTheme.secondaryText)
                }

                ForEach(days, id: \.id) { day in
                    Button {
                        selectedDate = day.date
                        selectedFilter = .today
                    } label: {
                        Text(day.label)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(day.isCurrentMonth ? SettingsTheme.primaryText : SettingsTheme.secondaryText)
                            .frame(width: 26, height: 26)
                            .background {
                                if day.isSelected {
                                    Circle()
                                        .fill(accentColor)
                                        .shadow(color: accentColor.opacity(0.55), radius: 8)
                                } else if day.isToday {
                                    Circle()
                                        .stroke(accentColor.opacity(0.7), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sidebarRow(
        icon: String,
        title: String,
        count: Int,
        filter: DayPlansTaskFilter,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = selectedFilter == filter

        return Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? accentColor : SettingsTheme.secondaryText)
            }
            .foregroundStyle(isSelected ? SettingsTheme.primaryText : SettingsTheme.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(accentColor.opacity(0.22))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func taskSection(title: String, tasks: [DayPlanItem], isCompletedSection: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(SettingsTheme.border)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(SettingsTheme.secondaryText)
                Rectangle()
                    .fill(SettingsTheme.border)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
            }

            VStack(spacing: 0) {
                if tasks.isEmpty {
                    Text(isCompletedSection ? "No completed tasks" : "No active tasks")
                        .font(SettingsTheme.captionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                } else {
                    ForEach(tasks) { task in
                        DayPlansWindowTaskRow(
                            task: task,
                            group: service.group(for: task),
                            groups: service.groups,
                            accentColor: accentColor,
                            onToggle: { toggle(task) },
                            onUpdate: { title, date, groupID in
                                service.updatePlan(task, title: title, date: date, groupID: groupID)
                            },
                            onDelete: { service.deletePlan(task) }
                        )
                        .onDrag {
                            draggedTaskID = task.id
                            return NSItemProvider(object: task.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: DayPlansTaskDropDelegate(
                                task: task,
                                tasks: tasks,
                                draggedTaskID: $draggedTaskID,
                                moveTask: moveTask
                            )
                        )

                        if task.id != tasks.last?.id {
                            Rectangle()
                                .fill(SettingsTheme.border.opacity(0.75))
                                .frame(height: 1)
                        }
                    }
                    .onMove { source, destination in
                        service.movePlans(tasks, from: source, to: destination)
                    }
                }

                if !isCompletedSection, selectedFilter != .completed {
                    addTaskRow
                }
            }
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

    private var addTaskRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accentColor)
            TextField("Add Task", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(SettingsTheme.primaryText)
                .focused($isNewTaskFocused)
                .onSubmit(addTask)

            groupPicker(selection: $newTaskGroupID)
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(SettingsTheme.border)
        )
        .padding(10)
    }

    private func groupPicker(selection: Binding<UUID?>) -> some View {
        Menu {
            Button("No Group") {
                selection.wrappedValue = nil
            }

            ForEach(service.groups) { group in
                Button {
                    selection.wrappedValue = group.id
                } label: {
                    Label(group.name, systemImage: selection.wrappedValue == group.id ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            HStack(spacing: 7) {
                if let group = service.groups.first(where: { $0.id == selection.wrappedValue }) {
                    Circle()
                        .fill(Color(hex: group.colorHex))
                        .frame(width: 10, height: 10)
                    Text(group.name)
                        .lineLimit(1)
                } else {
                    Circle()
                        .stroke(SettingsTheme.secondaryText, lineWidth: 1.4)
                        .frame(width: 10, height: 10)
                    Text("No Group")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(SettingsTheme.secondaryText)
            .frame(width: 112, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                Text("Drag & drop to reorder tasks")
            }
            .font(SettingsTheme.captionFont)
            .foregroundStyle(SettingsTheme.secondaryText)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SettingsTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SettingsTheme.border, lineWidth: 1)
                )
        )
    }

    private var canAddTask: Bool {
        !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var groupFilterDots: some View {
        HStack(spacing: 7) {
            Button {
                selectedGroupFilterID = nil
            } label: {
                Circle()
                    .fill(selectedGroupFilterID == nil ? accentColor : SettingsTheme.secondaryText.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("All groups")

            ForEach(service.groups) { group in
                Button {
                    selectedGroupFilterID = selectedGroupFilterID == group.id ? nil : group.id
                } label: {
                    Circle()
                        .fill(Color(hex: group.colorHex))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(selectedGroupFilterID == group.id ? 0.85 : 0), lineWidth: 2)
                        )
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(group.name)
            }
        }
        .frame(height: 42)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private func focusAddField() {
        isNewTaskFocused = true
    }

    private func addTask() {
        guard canAddTask else {
            isNewTaskFocused = true
            return
        }
        service.addPlan(title: newTaskTitle, date: selectedDate, groupID: newTaskGroupID)
        newTaskTitle = ""
        isNewTaskFocused = true
    }

    private func toggle(_ task: DayPlanItem) {
        withAnimation(.easeInOut(duration: 0.16)) {
            service.togglePlanCompletion(task)
        }
    }

    private func moveTask(_ draggedTaskID: UUID, before targetTaskID: UUID, in tasks: [DayPlanItem]) {
        guard let sourceIndex = tasks.firstIndex(where: { $0.id == draggedTaskID }),
              let targetIndex = tasks.firstIndex(where: { $0.id == targetTaskID }),
              sourceIndex != targetIndex else {
            return
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        service.movePlans(tasks, from: IndexSet(integer: sourceIndex), to: destination)
    }

    private func calendarDays() -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return []
        }

        var days: [CalendarDay] = []
        var date = firstWeek.start
        while date < lastWeek.end {
            let components = calendar.dateComponents([.day], from: date)
            days.append(
                CalendarDay(
                    id: DayPlanService.dayIdentifier(for: date, calendar: calendar),
                    date: date,
                    label: "\(components.day ?? 0)",
                    isCurrentMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                    isToday: calendar.isDateInToday(date),
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDay
        }
        return days
    }

    private func moveDisplayedMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }
}

private func dateFromDayIdentifier(_ dayIdentifier: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.calendar = .autoupdatingCurrent
    formatter.timeZone = .autoupdatingCurrent
    return formatter.date(from: dayIdentifier) ?? Date()
}

private struct DayPlansWindowTaskRow: View {
    let task: DayPlanItem
    let group: DayPlanGroup?
    let groups: [DayPlanGroup]
    let accentColor: Color
    let onToggle: () -> Void
    let onUpdate: (String, Date, UUID?) -> Void
    let onDelete: () -> Void

    private var statusColor: Color {
        if task.isCompleted {
            return group.map { Color(hex: $0.colorHex).opacity(0.72) } ?? SettingsTheme.secondaryText
        }
        return group.map { Color(hex: $0.colorHex) } ?? accentColor
    }

    @State private var title: String
    @State private var date: Date
    @State private var groupID: UUID?
    @State private var isDatePickerPresented = false

    init(
        task: DayPlanItem,
        group: DayPlanGroup?,
        groups: [DayPlanGroup],
        accentColor: Color,
        onToggle: @escaping () -> Void,
        onUpdate: @escaping (String, Date, UUID?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.task = task
        self.group = group
        self.groups = groups
        self.accentColor = accentColor
        self.onToggle = onToggle
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _title = State(initialValue: task.title)
        _date = State(initialValue: dateFromDayIdentifier(task.date))
        _groupID = State(initialValue: task.groupID)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.grid.3x3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SettingsTheme.secondaryText)

            Button(action: onToggle) {
                ZStack {
                    if task.isCompleted {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 18, height: 18)
                            .shadow(color: statusColor.opacity(0.45), radius: 8)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .stroke(statusColor.opacity(0.75), lineWidth: 2.5)
                            .frame(width: 20, height: 20)
                            .blur(radius: 2)
                        Circle()
                            .stroke(statusColor, lineWidth: 1.8)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(task.isCompleted ? SettingsTheme.secondaryText : SettingsTheme.primaryText)
                .strikethrough(task.isCompleted, color: SettingsTheme.secondaryText)
                .lineLimit(1)
                .onSubmit(commit)
                .onChange(of: title) { _, newValue in
                    if newValue.count > 120 {
                        title = String(newValue.prefix(120))
                    }
                }
                .onChange(of: task.title) { _, newValue in
                    if title != newValue { title = newValue }
                }

            Spacer()

            dateButton

            groupMenu

            Menu {
                Button("Save", action: commit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30, height: 30)
        }
        .padding(.horizontal, 26)
        .frame(height: 62)
    }

    private var dateButton: some View {
        Button {
            isDatePickerPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text(formattedDate)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(SettingsTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SettingsTheme.border.opacity(0.75), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Edit task date")
        .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
            DatePicker("", selection: $date, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(accentColor)
                .padding(12)
                .frame(width: 260)
                .background(SettingsTheme.background)
        }
        .onChange(of: date) { _, _ in commit() }
        .onChange(of: task.date) { _, newValue in
            let newDate = dateFromDayIdentifier(newValue)
            if !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: newDate) {
                date = newDate
            }
        }
    }

    private var formattedDate: String {
        if Calendar.autoupdatingCurrent.isDateInToday(date) {
            return "Today"
        }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()

    private var groupMenu: some View {
        Menu {
            Button("No Group") {
                groupID = nil
                commit()
            }

            ForEach(groups) { group in
                Button {
                    groupID = group.id
                    commit()
                } label: {
                    Label(group.name, systemImage: groupID == group.id ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            HStack(spacing: 7) {
                if let selectedGroup = groups.first(where: { $0.id == groupID }) {
                    Circle()
                        .fill(Color(hex: selectedGroup.colorHex))
                        .frame(width: 10, height: 10)
                    Text(selectedGroup.name)
                } else {
                    Circle()
                        .stroke(SettingsTheme.secondaryText, lineWidth: 1.4)
                        .frame(width: 10, height: 10)
                    Text("No Group")
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(SettingsTheme.secondaryText)
            .frame(width: 112, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onChange(of: task.groupID) { _, newValue in
            if groupID != newValue { groupID = newValue }
        }
    }

    private func commit() {
        onUpdate(title, date, groupID)
    }
}

private struct DayPlansTaskDropDelegate: DropDelegate {
    let task: DayPlanItem
    let tasks: [DayPlanItem]
    @Binding var draggedTaskID: UUID?
    let moveTask: (UUID, UUID, [DayPlanItem]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID, draggedTaskID != task.id else { return }
        moveTask(draggedTaskID, task.id, tasks)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTaskID = nil
        return true
    }
}

private enum DayPlansTaskFilter: String, CaseIterable, Identifiable {
    case today
    case all
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .all: "All"
        case .completed: "Completed"
        }
    }
}

private struct CalendarDay {
    let id: String
    let date: Date
    let label: String
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
}
