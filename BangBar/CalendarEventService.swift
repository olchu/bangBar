import AppKit
import Combine
import EventKit

struct UpcomingCalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
}

final class CalendarEventService: ObservableObject {
    @Published private(set) var nextEvent: UpcomingCalendarEvent?
    @Published private(set) var authorizationDenied = false

    private let eventStore = EKEventStore()
    private var lastRefreshDate: Date?

    func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            refresh()
        case .notDetermined, .writeOnly:
            requestAccess()
        case .denied, .restricted:
            authorizationDenied = true
            nextEvent = nil
            openCalendarPrivacySettings()
        @unknown default:
            authorizationDenied = true
            nextEvent = nil
        }
    }

    func refreshIfNeeded(now: Date) {
        guard !authorizationDenied else { return }

        if let lastRefreshDate,
           Calendar.current.component(.minute, from: lastRefreshDate) == Calendar.current.component(.minute, from: now),
           Calendar.current.isDate(lastRefreshDate, inSameDayAs: now) {
            return
        }

        lastRefreshDate = now
        start()
    }

    func requestAccessFromUserAction() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            refresh()
        case .notDetermined, .writeOnly:
            requestAccess()
        case .denied, .restricted:
            authorizationDenied = true
            nextEvent = nil
        @unknown default:
            authorizationDenied = true
            nextEvent = nil
        }
    }

    private func requestAccess() {
        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationDenied = !granted

                if granted {
                    self.refresh()
                } else {
                    self.nextEvent = nil
                }
            }
        }
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func refresh() {
        authorizationDenied = false

        let now = Date()
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endOfDay,
            calendars: nil
        )

        nextEvent = eventStore.events(matching: predicate)
            .filter { event in
                !event.isAllDay && event.endDate > now
            }
            .sorted { lhs, rhs in
                lhs.startDate < rhs.startDate
            }
            .first
            .map { event in
                UpcomingCalendarEvent(
                    title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: event.startDate,
                    endDate: event.endDate
                )
            }
    }
}
