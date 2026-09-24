import Combine
import Foundation

struct HabitDefinition: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var sortOrder: Int
    var creationDay: String
}

struct HabitDayRecord: Codable, Hashable, Identifiable {
    var day: String
    var completedHabitIDs: Set<UUID>

    var id: String { day }
}

struct HabitDaySummary: Identifiable {
    let day: String
    let date: Date
    let completedCount: Int
    let eligibleCount: Int

    var id: String { day }
    var completionRate: Double {
        guard eligibleCount > 0 else { return 0 }
        return Double(completedCount) / Double(eligibleCount)
    }
}

struct HabitStatistics {
    let currentStreak: Int
    let bestStreak: Int
    let thirtyDayRate: Double
}

struct HabitCompletionSummary {
    let completedCount: Int
    let eligibleCount: Int

    var completionRate: Double {
        guard eligibleCount > 0 else { return 0 }
        return Double(completedCount) / Double(eligibleCount)
    }
}

enum HabitDayState {
    case ineligible
    case incomplete
    case complete
}

@MainActor
final class HabitService: ObservableObject {
    static let shared = HabitService()

    @Published private(set) var habits: [HabitDefinition] = []
    @Published private(set) var records: [String: HabitDayRecord] = [:]
    @Published private(set) var currentDay = ""

    private struct StoredData: Codable {
        var version: Int
        var habits: [HabitDefinition]
        var records: [HabitDayRecord]
    }

    private static let storageVersion = 1
    private static let retentionDays = 365

    private let defaults: UserDefaults
    private var calendar: Calendar
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
        currentDay = Self.dayIdentifier(for: Date(), calendar: calendar)
        load()
        refreshDay()
        observeCalendarChanges()
    }

    var completedTodayCount: Int {
        habits.reduce(into: 0) { count, habit in
            if isCompletedToday(habit) { count += 1 }
        }
    }

    var todayCompletionRate: Double {
        guard !habits.isEmpty else { return 0 }
        return Double(completedTodayCount) / Double(habits.count)
    }

    func refreshDay(now: Date = Date()) {
        calendar = .autoupdatingCurrent
        let newDay = Self.dayIdentifier(for: now, calendar: calendar)
        if currentDay != newDay {
            currentDay = newDay
            objectWillChange.send()
        }
        pruneRecords(now: now)
    }

    @discardableResult
    func addHabit(title: String, now: Date = Date()) -> HabitDefinition? {
        let normalizedTitle = Self.normalizedTitle(title)
        guard !normalizedTitle.isEmpty else { return nil }

        refreshDay(now: now)
        let habit = HabitDefinition(
            id: UUID(),
            title: normalizedTitle,
            sortOrder: habits.count,
            creationDay: Self.dayIdentifier(for: now, calendar: calendar)
        )
        var updatedHabits = habits
        updatedHabits.append(habit)
        habits = updatedHabits
        persist()
        return habit
    }

    func renameHabit(_ habit: HabitDefinition, title: String) {
        let normalizedTitle = Self.normalizedTitle(title)
        guard !normalizedTitle.isEmpty,
              let index = habits.firstIndex(where: { $0.id == habit.id }) else {
            return
        }

        var updatedHabits = habits
        updatedHabits[index].title = normalizedTitle
        habits = updatedHabits
        persist()
    }

    func deleteHabit(_ habit: HabitDefinition) {
        habits = habits.filter { $0.id != habit.id }
        normalizeSortOrder()

        for day in Array(records.keys) {
            records[day]?.completedHabitIDs.remove(habit.id)
            if records[day]?.completedHabitIDs.isEmpty == true {
                records.removeValue(forKey: day)
            }
        }
        persist()
    }

    func moveHabit(_ habit: HabitDefinition, before target: HabitDefinition) {
        guard habit.id != target.id,
              let sourceIndex = habits.firstIndex(where: { $0.id == habit.id }),
              let targetIndex = habits.firstIndex(where: { $0.id == target.id }) else {
            return
        }

        var updatedHabits = habits
        let moved = updatedHabits.remove(at: sourceIndex)
        let destination = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        updatedHabits.insert(moved, at: destination)
        habits = updatedHabits
        normalizeSortOrder()
        persist()
    }

    func isCompletedToday(_ habit: HabitDefinition) -> Bool {
        records[currentDay]?.completedHabitIDs.contains(habit.id) == true
    }

    func toggleToday(_ habit: HabitDefinition, now: Date = Date()) {
        toggle(habit, on: now, now: now)
    }

    func dayState(for habit: HabitDefinition, on date: Date) -> HabitDayState {
        let day = Self.dayIdentifier(for: date, calendar: calendar)
        guard day >= habit.creationDay, day <= currentDay else { return .ineligible }
        return records[day]?.completedHabitIDs.contains(habit.id) == true ? .complete : .incomplete
    }

    func toggle(_ habit: HabitDefinition, on date: Date, now: Date = Date()) {
        refreshDay(now: now)
        let day = Self.dayIdentifier(for: date, calendar: calendar)
        guard day <= currentDay,
              let habitIndex = habits.firstIndex(where: { $0.id == habit.id }) else {
            return
        }

        // Marking a day before the habit existed backfills it, so the habit starts on that day.
        if day < habits[habitIndex].creationDay {
            var updatedHabits = habits
            updatedHabits[habitIndex].creationDay = day
            habits = updatedHabits
        }

        var record = records[day] ?? HabitDayRecord(day: day, completedHabitIDs: [])
        if record.completedHabitIDs.contains(habit.id) {
            record.completedHabitIDs.remove(habit.id)
        } else {
            record.completedHabitIDs.insert(habit.id)
        }

        if record.completedHabitIDs.isEmpty {
            records.removeValue(forKey: day)
        } else {
            records[day] = record
        }
        persist()
    }

    func aggregateCompletionRate(days: Int, now: Date = Date()) -> Double {
        aggregateCompletionSummary(days: days, now: now).completionRate
    }

    func aggregateCompletionSummary(days: Int, now: Date = Date()) -> HabitCompletionSummary {
        guard days > 0 else {
            return HabitCompletionSummary(completedCount: 0, eligibleCount: 0)
        }
        var completed = 0
        var eligible = 0

        for date in datesEndingToday(count: days, now: now) {
            let day = Self.dayIdentifier(for: date, calendar: calendar)
            let eligibleHabits = habits.filter { $0.creationDay <= day }
            eligible += eligibleHabits.count
            completed += eligibleHabits.reduce(into: 0) { count, habit in
                if records[day]?.completedHabitIDs.contains(habit.id) == true {
                    count += 1
                }
            }
        }

        return HabitCompletionSummary(completedCount: completed, eligibleCount: eligible)
    }

    func statistics(for habit: HabitDefinition, now: Date = Date()) -> HabitStatistics {
        HabitStatistics(
            currentStreak: calculateCurrentStreak(for: habit, now: now),
            bestStreak: bestStreak(for: habit, now: now),
            thirtyDayRate: completionRate(for: habit, days: 30, now: now)
        )
    }

    func currentStreak(for habit: HabitDefinition, now: Date = Date()) -> Int {
        calculateCurrentStreak(for: habit, now: now)
    }

    func recentDaySummaries(days: Int = 30, now: Date = Date()) -> [HabitDaySummary] {
        datesEndingToday(count: days, now: now).reversed().map { date in
            daySummary(for: date, now: now)
        }
    }

    func daySummary(for date: Date, now: Date = Date()) -> HabitDaySummary {
        let day = Self.dayIdentifier(for: date, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: date) <= today else {
            return HabitDaySummary(
                day: day,
                date: date,
                completedCount: 0,
                eligibleCount: 0
            )
        }

        let eligibleHabits = habits.filter { $0.creationDay <= day }
        let completed = eligibleHabits.reduce(into: 0) { count, habit in
            if records[day]?.completedHabitIDs.contains(habit.id) == true {
                count += 1
            }
        }
        return HabitDaySummary(
            day: day,
            date: date,
            completedCount: completed,
            eligibleCount: eligibleHabits.count
        )
    }

    static func dayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func normalizedTitle(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private func completionRate(for habit: HabitDefinition, days: Int, now: Date) -> Double {
        let eligibleDays = datesEndingToday(count: days, now: now).filter {
            Self.dayIdentifier(for: $0, calendar: calendar) >= habit.creationDay
        }
        guard !eligibleDays.isEmpty else { return 0 }

        let completed = eligibleDays.reduce(into: 0) { count, date in
            let day = Self.dayIdentifier(for: date, calendar: calendar)
            if records[day]?.completedHabitIDs.contains(habit.id) == true {
                count += 1
            }
        }
        return Double(completed) / Double(eligibleDays.count)
    }

    private func calculateCurrentStreak(for habit: HabitDefinition, now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        let todayKey = Self.dayIdentifier(for: today, calendar: calendar)
        let todayComplete = records[todayKey]?.completedHabitIDs.contains(habit.id) == true
        var cursor = todayComplete ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var streak = 0

        while true {
            let day = Self.dayIdentifier(for: cursor, calendar: calendar)
            guard day >= habit.creationDay,
                  records[day]?.completedHabitIDs.contains(habit.id) == true else {
                return streak
            }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return streak
            }
            cursor = previous
        }
    }

    private func bestStreak(for habit: HabitDefinition, now: Date) -> Int {
        let dates = datesEndingToday(count: Self.retentionDays, now: now).reversed()
        var best = 0
        var current = 0

        for date in dates {
            let day = Self.dayIdentifier(for: date, calendar: calendar)
            guard day >= habit.creationDay else { continue }

            if records[day]?.completedHabitIDs.contains(habit.id) == true {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    private func datesEndingToday(count: Int, now: Date) -> [Date] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<count).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private func normalizeSortOrder() {
        for index in habits.indices {
            habits[index].sortOrder = index
        }
    }

    private func pruneRecords(now: Date) {
        guard let cutoffDate = calendar.date(
            byAdding: .day,
            value: -(Self.retentionDays - 1),
            to: calendar.startOfDay(for: now)
        ) else {
            return
        }
        let cutoff = Self.dayIdentifier(for: cutoffDate, calendar: calendar)
        let originalCount = records.count
        records = records.filter { $0.key >= cutoff }
        if records.count != originalCount {
            persist()
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: BangBarSettings.Key.habitsData),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data),
              stored.version == Self.storageVersion else {
            habits = []
            records = [:]
            return
        }

        habits = stored.habits.sorted { $0.sortOrder < $1.sortOrder }
        normalizeSortOrder()
        records = Dictionary(uniqueKeysWithValues: stored.records.map { ($0.day, $0) })
    }

    private func persist() {
        let stored = StoredData(
            version: Self.storageVersion,
            habits: habits,
            records: records.values.sorted { $0.day < $1.day }
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: BangBarSettings.Key.habitsData)
    }

    private func observeCalendarChanges() {
        let center = NotificationCenter.default
        [
            Notification.Name.NSCalendarDayChanged,
            Notification.Name.NSSystemTimeZoneDidChange,
            Notification.Name.NSSystemClockDidChange
        ]
        .forEach { name in
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refreshDay() }
                .store(in: &cancellables)
        }
    }
}
