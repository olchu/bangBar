import Combine
import Foundation

struct DayPlanItem: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var date: String
    var isCompleted: Bool = false
}

@MainActor
final class DayPlanService: ObservableObject {
    static let shared = DayPlanService()

    @Published private(set) var items: [DayPlanItem] = []
    @Published private(set) var currentDay = ""

    private struct StoredData: Codable {
        var version: Int
        var items: [DayPlanItem]
    }

    private static let storageVersion = 1

    private let storageURL: URL
    private var calendar: Calendar
    private var cancellables: Set<AnyCancellable> = []

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        self.storageURL = Self.resolveStorageURL()
        currentDay = Self.dayIdentifier(for: Date(), calendar: calendar)
        reload()
        observeCalendarChanges()
    }

    var todaysItems: [DayPlanItem] {
        items.filter { $0.date == currentDay }
    }

    func refreshDay(now: Date = Date()) {
        calendar = .autoupdatingCurrent
        let newDay = Self.dayIdentifier(for: now, calendar: calendar)
        guard currentDay != newDay else { return }
        currentDay = newDay
        rolloverIncompletePlans(to: newDay)
    }

    func togglePlanCompletion(_ plan: DayPlanItem) {
        guard let index = items.firstIndex(where: { $0.id == plan.id }) else { return }
        items[index].isCompleted.toggle()
        persist()
    }

    private func rolloverIncompletePlans(to day: String) {
        var didChange = false
        for index in items.indices where !items[index].isCompleted && items[index].date < day {
            items[index].date = day
            didChange = true
        }
        guard didChange else { return }
        persist()
    }

    func reload() {
        guard let data = try? Data(contentsOf: storageURL) else {
            items = []
            return
        }

        guard let stored = try? JSONDecoder().decode(StoredData.self, from: data),
              stored.version == Self.storageVersion else {
            preserveUnreadableFile()
            items = []
            return
        }

        items = stored.items
        rolloverIncompletePlans(to: currentDay)
    }

    @discardableResult
    func addPlan(title: String, date: Date) -> DayPlanItem? {
        refreshDay()
        let normalizedTitle = Self.normalizedTitle(title)
        guard !normalizedTitle.isEmpty else { return nil }

        let plan = DayPlanItem(
            id: UUID(),
            title: normalizedTitle,
            date: Self.dayIdentifier(for: date, calendar: calendar)
        )
        items.append(plan)
        persist()
        return plan
    }

    func updatePlan(_ plan: DayPlanItem, title: String, date: Date) {
        let normalizedTitle = Self.normalizedTitle(title)
        guard !normalizedTitle.isEmpty,
              let index = items.firstIndex(where: { $0.id == plan.id }) else {
            return
        }

        items[index].title = normalizedTitle
        items[index].date = Self.dayIdentifier(for: date, calendar: calendar)
        persist()
    }

    func deletePlan(_ plan: DayPlanItem) {
        items.removeAll { $0.id == plan.id }
        persist()
    }

    func movePlans(_ orderedPlans: [DayPlanItem], from source: IndexSet, to destination: Int) {
        var reorderedPlans = orderedPlans
        reorderedPlans.move(fromOffsets: source, toOffset: destination)
        let reorderedIDs = reorderedPlans.map(\.id)
        let affectedIDs = Set(orderedPlans.map(\.id))
        let movedItems = reorderedIDs.compactMap { id in
            items.first { $0.id == id }
        }
        guard movedItems.count == reorderedPlans.count else { return }

        var movedIterator = movedItems.makeIterator()
        items = items.map { item in
            affectedIDs.contains(item.id) ? (movedIterator.next() ?? item) : item
        }
        persist()
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
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private func persist() {
        let stored = StoredData(version: Self.storageVersion, items: items)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: storageURL, options: .atomic)
    }

    private func preserveUnreadableFile() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storageURL.path) else { return }
        let salvageURL = storageURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? fm.moveItem(at: storageURL, to: salvageURL)
    }

    private static func resolveStorageURL() -> URL {
        let fm = FileManager.default
        let iCloudDriveRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

        let baseDirectory: URL
        if fm.fileExists(atPath: iCloudDriveRoot.path) {
            baseDirectory = iCloudDriveRoot.appendingPathComponent("BangBar/DayPlans", isDirectory: true)
        } else {
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            baseDirectory = appSupport.appendingPathComponent("BangBar/DayPlans", isDirectory: true)
        }

        return baseDirectory.appendingPathComponent("plans.json")
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
