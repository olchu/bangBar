import Combine
import Foundation

struct DayPlanItem: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var date: String
    var isCompleted: Bool = false
    var groupID: UUID? = nil
}

struct DayPlanGroup: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var colorHex: String
}

@MainActor
final class DayPlanService: ObservableObject {
    static let shared = DayPlanService()
    static let maximumGroupCount = 5

    @Published private(set) var items: [DayPlanItem] = []
    @Published private(set) var groups: [DayPlanGroup] = []
    @Published private(set) var currentDay = ""

    private struct StoredData: Codable {
        var version: Int
        var items: [DayPlanItem]
        var groups: [DayPlanGroup]?
    }

    private struct LegacyDayPlanItem: Codable {
        let id: UUID
        var title: String
        var date: String
        var isCompleted: Bool
    }

    private struct LegacyStoredData: Codable {
        var version: Int
        var items: [LegacyDayPlanItem]
    }

    private static let storageVersion = 2

    private let storageURL: URL
    private var calendar: Calendar
    private var cancellables: Set<AnyCancellable> = []
    private var externalStorageCancellable: AnyCancellable?
    private var externalStorageMonitoringClients = 0
    private var lastKnownStorageModificationDate: Date?

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        self.storageURL = Self.resolveStorageURL()
        currentDay = DayIdentifier.string(for: Date(), calendar: calendar)
        reload()
        observeCalendarChanges()
    }

    var todaysItems: [DayPlanItem] {
        items.filter { $0.date == currentDay }
    }

    func refreshDay(now: Date = Date()) {
        calendar = .autoupdatingCurrent
        let newDay = DayIdentifier.string(for: now, calendar: calendar)
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
            groups = []
            lastKnownStorageModificationDate = nil
            return
        }

        if let stored = try? JSONDecoder().decode(StoredData.self, from: data),
           stored.version == Self.storageVersion {
            groups = stored.groups ?? []
            items = stored.items.map { item in
                var migratedItem = item
                migratedItem.groupID = validGroupID(item.groupID, in: groups)
                return migratedItem
            }
            rolloverIncompletePlans(to: currentDay)
            lastKnownStorageModificationDate = storageModificationDate()
            return
        }

        if let legacy = try? JSONDecoder().decode(LegacyStoredData.self, from: data),
           legacy.version == 1 {
            groups = []
            items = legacy.items.map {
                DayPlanItem(
                    id: $0.id,
                    title: $0.title,
                    date: $0.date,
                    isCompleted: $0.isCompleted,
                    groupID: nil
                )
            }
            persist()
            rolloverIncompletePlans(to: currentDay)
            lastKnownStorageModificationDate = storageModificationDate()
            return
        }

        preserveUnreadableFile()
        items = []
        groups = []
        lastKnownStorageModificationDate = nil
    }

    func syncFromStorageIfChanged() {
        let modificationDate = storageModificationDate()
        guard modificationDate != lastKnownStorageModificationDate else { return }
        reload()
    }

    func beginExternalStorageMonitoring() {
        externalStorageMonitoringClients += 1
        guard externalStorageMonitoringClients == 1 else { return }

        syncFromStorageIfChanged()
        externalStorageCancellable = Timer.publish(every: 8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.syncFromStorageIfChanged()
            }
    }

    func endExternalStorageMonitoring() {
        externalStorageMonitoringClients = max(externalStorageMonitoringClients - 1, 0)
        guard externalStorageMonitoringClients == 0 else { return }
        externalStorageCancellable?.cancel()
        externalStorageCancellable = nil
    }

    @discardableResult
    func addPlan(title: String, date: Date, groupID: UUID? = nil) -> DayPlanItem? {
        refreshDay()
        let normalizedTitle = Self.normalizedTitle(title)
        guard !normalizedTitle.isEmpty else { return nil }

        let plan = DayPlanItem(
            id: UUID(),
            title: normalizedTitle,
            date: DayIdentifier.string(for: date, calendar: calendar),
            groupID: validGroupID(groupID)
        )
        items.append(plan)
        persist()
        return plan
    }

    func updatePlan(_ plan: DayPlanItem, title: String, date: Date, groupID: UUID? = nil) {
        let normalizedTitle = Self.normalizedTitle(title)
        guard !normalizedTitle.isEmpty,
              let index = items.firstIndex(where: { $0.id == plan.id }) else {
            return
        }

        items[index].title = normalizedTitle
        items[index].date = DayIdentifier.string(for: date, calendar: calendar)
        items[index].groupID = validGroupID(groupID)
        persist()
    }

    func group(for plan: DayPlanItem) -> DayPlanGroup? {
        guard let groupID = plan.groupID else { return nil }
        return groups.first { $0.id == groupID }
    }

    @discardableResult
    func addGroup(name: String, colorHex: String) -> DayPlanGroup? {
        let normalizedName = Self.normalizedGroupName(name)
        guard groups.count < Self.maximumGroupCount,
              !normalizedName.isEmpty else {
            return nil
        }

        let group = DayPlanGroup(
            id: UUID(),
            name: normalizedName,
            colorHex: Self.normalizedColorHex(colorHex)
        )
        groups.append(group)
        persist()
        return group
    }

    func updateGroup(_ group: DayPlanGroup, name: String, colorHex: String) {
        let normalizedName = Self.normalizedGroupName(name)
        guard !normalizedName.isEmpty,
              let index = groups.firstIndex(where: { $0.id == group.id }) else {
            return
        }

        groups[index].name = normalizedName
        groups[index].colorHex = Self.normalizedColorHex(colorHex)
        persist()
    }

    func deleteGroup(_ group: DayPlanGroup) {
        groups.removeAll { $0.id == group.id }
        for index in items.indices where items[index].groupID == group.id {
            items[index].groupID = nil
        }
        persist()
    }

    func deletePlan(_ plan: DayPlanItem) {
        items.removeAll { $0.id == plan.id }
        persist()
    }

    func movePlans(_ orderedPlans: [DayPlanItem], from source: IndexSet, to destination: Int) {
        var reorderedPlans = orderedPlans
        reorderedPlans.moveElements(from: source, to: destination)
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

    private static func normalizedTitle(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private static func normalizedGroupName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
    }

    private static func normalizedColorHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "#FF3B30" : trimmed
    }

    private func validGroupID(_ groupID: UUID?) -> UUID? {
        validGroupID(groupID, in: groups)
    }

    private func validGroupID(_ groupID: UUID?, in groups: [DayPlanGroup]) -> UUID? {
        guard let groupID, groups.contains(where: { $0.id == groupID }) else { return nil }
        return groupID
    }

    private func persist() {
        let stored = StoredData(version: Self.storageVersion, items: items, groups: groups)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: storageURL, options: .atomic)
        lastKnownStorageModificationDate = storageModificationDate()
    }

    private func storageModificationDate() -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: storageURL.path)[.modificationDate] as? Date
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
        DayIdentifier.changes
            .sink { [weak self] in self?.refreshDay() }
            .store(in: &cancellables)
    }

}

private extension Array {
    mutating func moveElements(from source: IndexSet, to destination: Int) {
        let movingElements = source.map { self[$0] }
        for index in source.sorted(by: >) {
            remove(at: index)
        }

        let movedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = Swift.max(0, Swift.min(destination - movedBeforeDestination, count))
        insert(contentsOf: movingElements, at: insertionIndex)
    }
}
