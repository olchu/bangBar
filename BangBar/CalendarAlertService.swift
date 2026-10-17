import AppKit
import EventKit
import SwiftUI

extension Notification.Name {
    static let bangBarPreviewCalendarAlert = Notification.Name("bangBarPreviewCalendarAlert")
}

private enum CalendarAlertAttendeeStatus {
    case accepted
    case tentative
    case declined
    case pending
    case none
}

private struct CalendarAlertAttendee {
    let name: String
    let status: CalendarAlertAttendeeStatus
}

private struct CalendarAlertEvent {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let calendarColor: NSColor
    let location: String?
    let notes: String?
    let organizerName: String?
    let attendeeCount: Int
    let attendees: [CalendarAlertAttendee]
    let meetingURL: URL?
}

@MainActor
final class CalendarAlertService {
    private let eventStore = EKEventStore()
    private var timer: Timer?
    private var alertWindow: NSWindow?
    private var shownOccurrenceIDs = Set<String>()
    private var snoozedEvent: CalendarAlertEvent?
    private var snoozedUntil: Date?
    private var observers: [NSObjectProtocol] = []
    private var settings = AlertSettings.current

    /// The settings alerts depend on. Any defaults write in the app posts a change notification, and
    /// re-querying EventKit for unrelated keys would be wasted work.
    private struct AlertSettings: Equatable {
        var isEnabled: Bool
        var leadMinutes: Int
        var selectedCalendarIDs: String
        var blurIntensity: Int

        static var current: AlertSettings {
            let defaults = UserDefaults.standard
            return AlertSettings(
                isEnabled: defaults.bool(forKey: BangBarSettings.Key.calendarAlertsEnabled),
                leadMinutes: defaults.integer(forKey: BangBarSettings.Key.calendarAlertLeadMinutes),
                selectedCalendarIDs: defaults.string(forKey: BangBarSettings.Key.selectedCalendarIds) ?? "",
                blurIntensity: defaults.integer(forKey: BangBarSettings.Key.calendarAlertBlurIntensity)
            )
        }
    }

    func start() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.settingsDidChange() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkEvents() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .bangBarPreviewCalendarAlert,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.showPreview() }
            }
        )
        settings = .current
        updateTimer()
    }

    private func settingsDidChange() {
        let previous = settings
        settings = .current
        if settings.blurIntensity != previous.blurIntensity {
            applyWindowBlur()
        }
        var timerSettings = settings
        timerSettings.blurIntensity = previous.blurIntensity
        if timerSettings != previous {
            updateTimer()
        }
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil

        guard settings.isEnabled else {
            dismissAlert()
            return
        }

        checkEvents()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkEvents() }
        }
        timer?.tolerance = 2
    }

    private func checkEvents(now: Date = Date()) {
        guard settings.isEnabled,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return
        }

        if let snoozedEvent, let snoozedUntil, now >= snoozedUntil {
            self.snoozedEvent = nil
            self.snoozedUntil = nil
            present(snoozedEvent)
            return
        }

        let triggerOffset = TimeInterval(settings.leadMinutes * 60)
        let lateArrivalGrace = max(TimeInterval(10 * 60), triggerOffset + 2 * 60)
        let searchStart = now.addingTimeInterval(-lateArrivalGrace)
        let searchEnd = now.addingTimeInterval(triggerOffset + 45)
        let calendars = eventStore.selectedEventCalendars(fromRaw: settings.selectedCalendarIDs)

        guard calendars?.isEmpty != true else { return }

        let events = eventStore.events(
            matching: eventStore.predicateForEvents(
                withStart: searchStart,
                end: searchEnd,
                calendars: calendars
            )
        )
        guard let event = events
            .filter({ !$0.isAllDay && $0.endDate > now && $0.startDate <= searchEnd })
            .sorted(by: { $0.startDate < $1.startDate })
            .first(where: { event in
                let triggerDate = event.startDate.addingTimeInterval(-triggerOffset)
                return triggerDate <= now
                    && now.timeIntervalSince(triggerDate) <= lateArrivalGrace
                    && !shownOccurrenceIDs.contains(occurrenceID(for: event))
            }) else {
            return
        }

        shownOccurrenceIDs.insert(occurrenceID(for: event))
        trimShownOccurrences()
        present(
            CalendarAlertEvent(
                identifier: occurrenceID(for: event),
                title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: event.startDate,
                endDate: event.endDate,
                calendarTitle: event.calendar.title,
                calendarColor: NSColor(cgColor: event.calendar.cgColor) ?? .systemRed,
                location: cleaned(event.location),
                notes: cleaned(event.notes),
                organizerName: cleaned(event.organizer?.name),
                attendeeCount: event.attendees?.count ?? 0,
                attendees: event.attendees?.compactMap { participant in
                    guard let name = cleaned(participant.name) else { return nil }
                    return CalendarAlertAttendee(
                        name: name,
                        status: attendeeStatus(for: participant.participantStatus)
                    )
                } ?? [],
                meetingURL: meetingURL(for: event)
            )
        )
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func meetingURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = []

        if let url = event.url {
            candidates.append(url)
        }

        for text in [event.location, event.notes].compactMap({ $0 }) {
            guard let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
            ) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            candidates.append(
                contentsOf: detector.matches(in: text, options: [], range: range).compactMap(\.url)
            )
        }

        return candidates.first { meetingURLPriority($0) > 0 } ?? candidates.first
    }

    private func meetingURLPriority(_ url: URL) -> Int {
        let value = url.absoluteString.lowercased()
        let meetingHosts = ["zoom.", "zoomgov.", "meet.google.", "teams.microsoft.", "teams.live.", "webex."]
        return meetingHosts.contains(where: value.contains) ? 1 : 0
    }

    private func attendeeStatus(for status: EKParticipantStatus) -> CalendarAlertAttendeeStatus {
        switch status {
        case .accepted, .completed:
            return .accepted
        case .tentative:
            return .tentative
        case .declined:
            return .declined
        case .pending, .delegated, .inProcess:
            return .pending
        case .unknown:
            return .none
        @unknown default:
            return .none
        }
    }

    private func occurrenceID(for event: EKEvent) -> String {
        "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
    }

    private func trimShownOccurrences() {
        if shownOccurrenceIDs.count > 100 {
            shownOccurrenceIDs.removeAll(keepingCapacity: true)
        }
    }

    private func showPreview() {
        let now = Date()
        present(
            CalendarAlertEvent(
                identifier: "preview",
                title: "Design review",
                startDate: now,
                endDate: now.addingTimeInterval(45 * 60),
                calendarTitle: "Work",
                calendarColor: .systemBlue,
                location: "Conference room",
                notes: "**Review:** the latest product direction.\n- Agree on the next steps",
                organizerName: "Olchu Studio",
                attendeeCount: 4,
                attendees: [
                    CalendarAlertAttendee(name: "Anna Petrova", status: .accepted),
                    CalendarAlertAttendee(name: "Mark Lee", status: .accepted),
                    CalendarAlertAttendee(name: "Sofia Chen", status: .tentative),
                    CalendarAlertAttendee(name: "Noah Wilson", status: .pending)
                ],
                meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
            )
        )
    }

    private func present(_ event: CalendarAlertEvent) {
        dismissAlert()

        guard let screen = NSScreen.main else { return }
        let content = CalendarAlertView(
            event: event,
            onDismiss: { [weak self] in self?.dismissAlert() },
            onSnooze: { [weak self] minutes in self?.snooze(event, minutes: minutes) }
        )
        let window = CalendarAlertWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentViewController = NSHostingController(rootView: content)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.setFrame(screen.frame, display: true)

        alertWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        applyWindowBlur()
    }

    private func applyWindowBlur() {
        guard let alertWindow else { return }
        alertWindow.isOpaque = false
        alertWindow.backgroundColor = .clear
        alertWindow.alphaValue = 1
        let blurRadius = UserDefaults.standard.integer(
            forKey: BangBarSettings.Key.calendarAlertBlurIntensity
        )
        WindowBackgroundBlur.setRadius(UInt32(clampedBlurRadius(blurRadius)), for: alertWindow)
    }

    private func clampedBlurRadius(_ radius: Int) -> Int {
        min(
            max(radius, BangBarSettings.calendarAlertBlurRadiusRange.lowerBound),
            BangBarSettings.calendarAlertBlurRadiusRange.upperBound
        )
    }

    private func snooze(_ event: CalendarAlertEvent, minutes: Int) {
        snoozedEvent = event
        snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        dismissAlert()
    }

    private func dismissAlert() {
        alertWindow?.orderOut(nil)
        alertWindow?.close()
        alertWindow = nil
    }
}

private final class CalendarAlertWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct CalendarAlertView: View {
    let event: CalendarAlertEvent
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void

    @AppStorage(BangBarSettings.Key.calendarAlertBackgroundOpacity)
    private var backgroundOpacity = 62
    @AppStorage(BangBarSettings.Key.calendarAlertBlurIntensity)
    private var blurIntensity = BangBarSettings.defaultCalendarAlertBlurRadius
    @State private var appeared = false

    private var calendarColor: Color { Color(nsColor: event.calendarColor) }
    private var normalizedBackgroundOpacity: Double {
        Double(min(max(backgroundOpacity, 0), 100)) / 100
    }

    var body: some View {
        ZStack {
            Color.black.opacity(normalizedBackgroundOpacity)

            RadialGradient(
                colors: [
                    calendarColor.opacity(0.18),
                    calendarColor.opacity(0.05),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 720
            )

            Circle()
                .fill(calendarColor.opacity(0.11))
                .frame(width: 560, height: 560)
                .blur(radius: 100)

            VStack(spacing: 0) {
                ZStack {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(calendarColor)
                            .frame(width: 10, height: 10)
                            .shadow(color: calendarColor, radius: 8)

                        Text(event.calendarTitle.uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundStyle(.white.opacity(0.78))

                    HStack {
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(countdownText(at: context.date))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundStyle(calendarColor)
                                .padding(.horizontal, 20)
                                .frame(height: 38)
                                .overlay(
                                    Capsule()
                                        .stroke(calendarColor.opacity(0.48), lineWidth: 1)
                                )
                        }
                    }
                }
                .frame(width: 620, height: 40)

                Text(event.title.isEmpty ? "Calendar event" : event.title)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .frame(width: 760)
                    .padding(.top, 24)

                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 21, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 15) {
                    if event.location != nil || event.meetingURL != nil {
                        Label {
                            HStack(spacing: 9) {
                                if let location = event.location {
                                    Text(location)
                                }
                                if event.location != nil, event.meetingURL != nil {
                                    Text("•").foregroundStyle(calendarColor)
                                }
                                if event.meetingURL != nil {
                                    Text("Online")
                                }
                            }
                        } icon: {
                            Image(systemName: "display")
                        }
                    }

                    if let organizerName = event.organizerName {
                        Label(
                            participantDescription(organizerName: organizerName),
                            systemImage: "person.2"
                        )
                    }
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 440, alignment: .leading)
                .padding(.top, 38)

                if !event.attendees.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(event.attendees.prefix(3).enumerated()), id: \.offset) { index, attendee in
                            if index > 0 {
                                Text("•")
                                    .foregroundStyle(.white.opacity(0.34))
                            }

                            HStack(spacing: 6) {
                                Text(attendee.name)
                                    .foregroundStyle(.white.opacity(0.82))
                                attendeeStatus(attendee.status)
                            }
                        }

                        let remainingCount = max(event.attendeeCount - 3, 0)
                        if remainingCount > 0 {
                            Text("•")
                                .foregroundStyle(.white.opacity(0.34))
                            Text("+\(remainingCount)")
                                .foregroundStyle(.white.opacity(0.52))
                        }
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .frame(width: 620, alignment: .leading)
                    .padding(.top, 28)
                }

                if let notes = event.notes {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AGENDA")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(calendarColor)

                        CalendarAlertNotesText(notes: notes, accentColor: calendarColor)
                            .lineLimit(3)
                    }
                    .frame(width: 690, alignment: .leading)
                    .padding(.top, 58)
                }

                Spacer(minLength: 30)

                HStack(spacing: 18) {
                    if let meetingURL = event.meetingURL {
                        Button("Join meeting") {
                            NSWorkspace.shared.open(meetingURL)
                            onDismiss()
                        }
                        .buttonStyle(
                            CalendarAlertPrimaryButtonStyle(
                                accentColor: calendarColor,
                                width: 260
                            )
                        )
                        .keyboardShortcut(.defaultAction)
                    }

                    Menu {
                        Button("5 minutes") { onSnooze(5) }
                        Button("10 minutes") { onSnooze(10) }
                        Button("15 minutes") { onSnooze(15) }
                    } label: {
                        HStack(spacing: 14) {
                            Text("Snooze")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 260, height: 54)
                        .background(.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(CalendarAlertPlainButtonStyle())
                }

                HStack(spacing: 22) {
                    if event.meetingURL != nil { Text("↵  Join") }
                    Text("S  Snooze")
                    Text("Esc  Close")
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.32))
                .padding(.top, 24)
            }
            .frame(width: 940, height: 820)
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 54, height: 54)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .background {
            CalendarAlertWindowBlurUpdater(radius: blurIntensity)

            Button("") { onSnooze(5) }
                .keyboardShortcut("s", modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    private func participantDescription(organizerName: String) -> String {
        guard event.attendeeCount > 0 else { return organizerName }
        return "\(organizerName) · \(event.attendeeCount) participants"
    }

    private func countdownText(at date: Date) -> String {
        let remaining = event.startDate.timeIntervalSince(date)
        guard remaining > 0 else { return "NOW" }
        let minutes = max(Int(ceil(remaining / 60)), 1)
        return "IN \(minutes) MIN"
    }

    @ViewBuilder
    private func attendeeStatus(_ status: CalendarAlertAttendeeStatus) -> some View {
        switch status {
        case .accepted:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(calendarColor)
        case .tentative, .pending:
            Text("?")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow.opacity(0.9))
        case .declined:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red.opacity(0.9))
        case .none:
            EmptyView()
        }
    }
}

private struct CalendarAlertNotesText: View {
    let notes: String
    let accentColor: Color

    var body: some View {
        Text(CalendarAlertNotesFormatter.attributedString(from: notes))
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .tint(accentColor)
    }
}

private enum CalendarAlertNotesFormatter {
    static func attributedString(from source: String) -> AttributedString {
        if containsHTML(in: source), let attributedHTML = attributedHTML(from: source) {
            return AttributedString(attributedHTML)
        }

        return (try? AttributedString(
            markdown: normalizedMarkdown(source),
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(source)
    }

    private static func normalizedMarkdown(_ source: String) -> String {
        source
            .components(separatedBy: .newlines)
            .map { line in
                if let headingPrefix = line.range(
                    of: #"^\s{0,3}#{1,6}\s+"#,
                    options: .regularExpression
                ) {
                    return "**\(line[headingPrefix.upperBound...])**"
                }

                return line
                    .replacingOccurrences(
                        of: #"^(\s*)[-+*]\s+\[[xX]\]\s+"#,
                        with: "$1☑ ",
                        options: .regularExpression
                    )
                    .replacingOccurrences(
                        of: #"^(\s*)[-+*]\s+\[ \]\s+"#,
                        with: "$1☐ ",
                        options: .regularExpression
                    )
                    .replacingOccurrences(
                        of: #"^(\s*)[-+*]\s+"#,
                        with: "$1• ",
                        options: .regularExpression
                    )
                    .replacingOccurrences(
                        of: #"^(\s*)>\s?"#,
                        with: "$1› ",
                        options: .regularExpression
                    )
            }
            .joined(separator: "\n")
    }

    private static func containsHTML(in source: String) -> Bool {
        source.range(
            of: #"</?(?:a|b|strong|i|em|u|br|p|div|ul|ol|li|code|pre|blockquote|h[1-6])(?:\s[^>]*)?/?>"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func attributedHTML(from source: String) -> NSAttributedString? {
        let safeSource = source
            .replacingOccurrences(
                of: #"<(script|style|iframe|object)\b[^>]*>.*?</\1\s*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<(?:img|link|meta|embed)\b[^>]*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

        guard let data = safeSource.data(using: .utf8),
              let imported = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return nil
        }

        let fullRange = NSRange(location: 0, length: imported.length)
        imported.removeAttribute(.foregroundColor, range: fullRange)
        imported.removeAttribute(.backgroundColor, range: fullRange)
        imported.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let sourceFont = value as? NSFont
            let traits = sourceFont?.fontDescriptor.symbolicTraits ?? []
            let weight: NSFont.Weight = traits.contains(.bold) ? .semibold : .regular
            var font = NSFont.systemFont(ofSize: 16, weight: weight)

            if traits.contains(.italic) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }

            imported.addAttribute(.font, value: font, range: range)
        }

        if let trailingWhitespace = imported.string.range(
            of: #"\s+$"#,
            options: .regularExpression
        ) {
            imported.deleteCharacters(in: NSRange(trailingWhitespace, in: imported.string))
        }

        return imported
    }
}

private struct CalendarAlertWindowBlurUpdater: NSViewRepresentable {
    let radius: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        applyBlur(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyBlur(from: nsView)
    }

    private func applyBlur(from view: NSView) {
        guard let window = view.window else { return }
        WindowBackgroundBlur.setRadius(UInt32(clampedRadius), for: window)
    }

    private var clampedRadius: Int {
        min(
            max(radius, BangBarSettings.calendarAlertBlurRadiusRange.lowerBound),
            BangBarSettings.calendarAlertBlurRadiusRange.upperBound
        )
    }
}

private struct CalendarAlertPrimaryButtonStyle: ButtonStyle {
    let accentColor: Color
    var width: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: width, height: 54)
            .background(accentColor.opacity(configuration.isPressed ? 0.72 : 1))
            .shadow(color: accentColor.opacity(0.28), radius: 18)
            .clipShape(Capsule())
    }
}

private struct CalendarAlertPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.78))
            .frame(width: 130, height: 54)
            .contentShape(Rectangle())
    }
}
