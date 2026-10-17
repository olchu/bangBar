import AppKit
import Combine
import EventKit

struct UpcomingCalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarColor: NSColor
}

final class CalendarEventService: ObservableObject {
    enum AuthorizationState {
        case unknown
        case requesting
        case authorized
        case denied
        case failed(String)
    }

    @Published private(set) var upcomingEvents: [UpcomingCalendarEvent] = []
    @Published private(set) var authorizationState: AuthorizationState = .unknown

    var nextEvent: UpcomingCalendarEvent? {
        upcomingEvents.first
    }

    var authorizationDenied: Bool {
        if case .denied = authorizationState {
            return true
        }

        return false
    }

    private let eventStore = EKEventStore()
    private var lastRefreshDate: Date?
    private var lastCalendarSelectionRaw: String?

    func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            authorizationState = .authorized
            refresh()
        case .notDetermined, .writeOnly:
            authorizationState = .unknown
            upcomingEvents = []
        case .denied, .restricted:
            authorizationState = .denied
            upcomingEvents = []
        @unknown default:
            authorizationState = .failed("Unknown calendar authorization status")
            upcomingEvents = []
        }
    }

    func refreshIfNeeded(now: Date) {
        guard !authorizationDenied else { return }

        let calendarSelectionRaw = UserDefaults.standard.string(forKey: BangBarSettings.Key.selectedCalendarIds) ?? ""

        if let lastRefreshDate,
           Calendar.current.component(.minute, from: lastRefreshDate) == Calendar.current.component(.minute, from: now),
           Calendar.current.isDate(lastRefreshDate, inSameDayAs: now),
           lastCalendarSelectionRaw == calendarSelectionRaw {
            return
        }

        lastRefreshDate = now
        lastCalendarSelectionRaw = calendarSelectionRaw
        start()
    }

    func requestAccessFromUserAction() {
        if authorizationDenied {
            openPrivacySettings(anchor: "Privacy_Calendars")
            return
        }

        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            authorizationState = .authorized
            refresh()
        case .notDetermined, .writeOnly:
            requestAccess()
        case .denied, .restricted:
            authorizationState = .denied
            upcomingEvents = []
            openPrivacySettings(anchor: "Privacy_Calendars")
        @unknown default:
            authorizationState = .failed("Unknown calendar authorization status")
            upcomingEvents = []
        }
    }

    private func requestAccess() {
        authorizationState = .requesting
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if granted {
                    self.authorizationState = .authorized
                    self.refresh()
                } else if let error {
                    self.authorizationState = .failed(error.localizedDescription)
                    self.upcomingEvents = []
                    NSLog("BangBar calendar access request failed: %@", error.localizedDescription)
                } else {
                    self.authorizationState = .denied
                    self.upcomingEvents = []
                }
            }
        }
    }

    private func refresh() {
        let now = Date()
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        let calendars = eventStore.selectedEventCalendars(
            fromRaw: UserDefaults.standard.string(forKey: BangBarSettings.Key.selectedCalendarIds) ?? ""
        )

        if calendars?.isEmpty == true {
            upcomingEvents = []
            return
        }

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endOfDay,
            calendars: calendars
        )

        upcomingEvents = eventStore.events(matching: predicate)
            .filter { event in
                !event.isAllDay && event.endDate > now
            }
            .sorted { lhs, rhs in
                lhs.startDate < rhs.startDate
            }
            .prefix(2)
            .map { event in
                UpcomingCalendarEvent(
                    title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarColor: NSColor(cgColor: event.calendar.cgColor) ?? .white
                )
            }
    }
}

extension EKEventStore {
    /// The event calendars picked in Settings: nil means all of them, empty means none.
    func selectedEventCalendars(fromRaw rawValue: String) -> [EKCalendar]? {
        BangBarSettings.selectedCalendarIds(from: rawValue).map { ids in
            calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
    }
}
