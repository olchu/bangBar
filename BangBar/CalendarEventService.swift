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

    @Published private(set) var nextEvent: UpcomingCalendarEvent?
    @Published private(set) var authorizationState: AuthorizationState = .unknown

    var authorizationDenied: Bool {
        if case .denied = authorizationState {
            return true
        }

        return false
    }

    private let eventStore = EKEventStore()
    private var lastRefreshDate: Date?

    func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            authorizationState = .authorized
            refresh()
        case .notDetermined, .writeOnly:
            authorizationState = .unknown
            nextEvent = nil
        case .denied, .restricted:
            authorizationState = .denied
            nextEvent = nil
        @unknown default:
            authorizationState = .failed("Unknown calendar authorization status")
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
        if authorizationDenied {
            openCalendarPrivacySettings()
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
            nextEvent = nil
            openCalendarPrivacySettings()
        @unknown default:
            authorizationState = .failed("Unknown calendar authorization status")
            nextEvent = nil
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
                    self.nextEvent = nil
                    NSLog("BangBar calendar access request failed: %@", error.localizedDescription)
                } else {
                    self.authorizationState = .denied
                    self.nextEvent = nil
                }
            }
        }
    }

    private func openCalendarPrivacySettings() {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    private func refresh() {
        authorizationState = .authorized

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
                    endDate: event.endDate,
                    calendarColor: NSColor(cgColor: event.calendar.cgColor) ?? .white
                )
            }
    }
}
