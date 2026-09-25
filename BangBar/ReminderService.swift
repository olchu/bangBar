import AppKit
import Combine
import EventKit

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isOverdue: Bool
}

final class ReminderService: ObservableObject {
    enum AuthorizationState {
        case unknown
        case requesting
        case authorized
        case denied
        case failed(String)
    }

    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var authorizationState: AuthorizationState = .unknown

    private let store = EKEventStore()
    private var pollTimer: Timer?
    private var storeObserver: NSObjectProtocol?

    deinit {
        pollTimer?.invalidate()
        if let obs = storeObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func start() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            authorizationState = .authorized
            startPolling()
            refresh()
        case .notDetermined, .writeOnly:
            authorizationState = .unknown
            items = []
        case .denied, .restricted:
            authorizationState = .denied
            items = []
        @unknown default:
            authorizationState = .failed("Unknown status")
            items = []
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
    }

    func requestAccessFromUserAction() {
        if case .denied = authorizationState {
            openPrivacySettings()
            return
        }

        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            authorizationState = .authorized
            refresh()
        case .notDetermined, .writeOnly:
            requestAccess()
        case .denied, .restricted:
            authorizationState = .denied
            items = []
            openPrivacySettings()
        @unknown default:
            authorizationState = .failed("Unknown status")
            items = []
        }
    }

    func refresh() {
        guard case .authorized = authorizationState else { return }
        let now = Date()
        let selectedListId = UserDefaults.standard.string(forKey: BangBarSettings.Key.reminderListId) ?? ""
        let filterCalendars: [EKCalendar]?
        if selectedListId.isEmpty {
            filterCalendars = nil
        } else {
            let cal = store.calendars(for: .reminder).first { $0.calendarIdentifier == selectedListId }
            filterCalendars = cal.map { [$0] }
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: filterCalendars
        )
        store.fetchReminders(matching: predicate) { [weak self] fetched in
            guard let self, let fetched else { return }
            let startOfToday = Calendar.current.startOfDay(for: now)
            let normalized: [ReminderItem] = fetched
                .filter { !$0.isCompleted }
                .compactMap { reminder in
                    guard let title = reminder.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    let isOverdue = dueDate.map { $0 < startOfToday } ?? false
                    return ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        dueDate: dueDate,
                        isOverdue: isOverdue
                    )
                }
                .sorted { lhs, rhs in
                    let lp = self.sortPriority(lhs)
                    let rp = self.sortPriority(rhs)
                    if lp != rp { return lp < rp }
                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (l?, r?): return l < r
                    case (nil, nil): return lhs.title < rhs.title
                    default: return false
                    }
                }
            DispatchQueue.main.async {
                self.items = Array(normalized.prefix(10))
            }
        }
    }

    private func sortPriority(_ item: ReminderItem) -> Int {
        guard let date = item.dueDate else { return 0 }
        if item.isOverdue { return 1 }
        if Calendar.current.isDateInToday(date) { return 2 }
        return 3
    }

    func completeReminder(id: String) {
        guard case .authorized = authorizationState else { return }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            NSLog("BangBar: failed to complete reminder: %@", error.localizedDescription)
        }
    }

    func addReminder(title: String, dueDate: Date?) {
        guard case .authorized = authorizationState else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        let selectedListId = UserDefaults.standard.string(forKey: BangBarSettings.Key.reminderListId) ?? ""
        if !selectedListId.isEmpty,
           let cal = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == selectedListId }) {
            reminder.calendar = cal
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }
        if let date = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
        }
        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            NSLog("BangBar: failed to save reminder: %@", error.localizedDescription)
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        pollTimer?.tolerance = 5
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    private func requestAccess() {
        authorizationState = .requesting
        store.requestFullAccessToReminders { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.authorizationState = .authorized
                    self.startPolling()
                    self.refresh()
                } else if let error {
                    self.authorizationState = .failed(error.localizedDescription)
                    self.items = []
                    NSLog("BangBar reminders access failed: %@", error.localizedDescription)
                } else {
                    self.authorizationState = .denied
                    self.items = []
                }
            }
        }
    }

    private func openPrivacySettings() {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]
        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}
