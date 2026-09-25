import Combine
import AppKit
import Foundation
import SwiftUI

struct GitHubWidget: View {
    @ObservedObject var contributions: GitHubContributionsService
    let isActive: Bool
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @AppStorage(BangBarSettings.Key.githubUsername) private var username = ""

    var body: some View {
        VStack(alignment: .leading) {
            if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState("Add username in Settings")
            } else if let errorMessage = contributions.errorMessage {
                emptyState(errorMessage)
            } else {
                VStack(spacing: 10) {
                    contributionGrid

                    Text("\(contributions.totalCount) contributions in the last year")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .opacity(contributions.isLoading && contributions.weeks.isEmpty ? 0.35 : 1)
            }
        }
        .frame(
            width: PanelLayout.githubWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .task(id: RefreshTaskID(username: username, isActive: isActive)) {
            guard isActive else { return }
            while !Task.isCancelled {
                await contributions.load(username: username)

                do {
                    try await Task.sleep(for: GitHubContributionsService.refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private struct RefreshTaskID: Hashable {
        let username: String
        let isActive: Bool
    }

    private var accentColor: Color { Color(hex: accentColorHex) }

    private var contributionGrid: some View {
        HStack(alignment: .top, spacing: 5) {
            VStack(spacing: 3) {
                Color.clear
                    .frame(width: 18, height: 9)

                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        Text(weekdayLabel(for: dayIndex))
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 18, height: 7, alignment: .leading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ZStack(alignment: .topLeading) {
                    ForEach(contributions.visibleMonthMarkers) { marker in
                        Text(marker.title)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.68))
                            .offset(x: CGFloat(marker.weekIndex) * 10)
                    }
                }
                .frame(width: 127, height: 9, alignment: .leading)

                HStack(spacing: 3) {
                    ForEach(contributions.visibleWeeks) { week in
                        VStack(spacing: 3) {
                            ForEach(week.days) { day in
                                if day.date < tomorrow {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(color(for: day.level))
                                        .frame(width: 7, height: 7)
                                        .overlay(GitHubContributionTooltipView(text: day.tooltip))
                                } else {
                                    Color.clear
                                        .frame(width: 7, height: 7)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 127, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func weekdayLabel(for index: Int) -> String {
        switch index {
        case 1: "Mon"
        case 3: "Wed"
        case 5: "Fri"
        default: ""
        }
    }

    private var tomorrow: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: today)!
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1: accentColor.opacity(0.24)
        case 2: accentColor.opacity(0.46)
        case 3: accentColor.opacity(0.72)
        case 4...: accentColor
        default: Color.white.opacity(0.09)
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(accentColor.opacity(0.72))

            Text(message)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GitHubContributionTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> GitHubContributionTooltipNSView {
        let view = GitHubContributionTooltipNSView(frame: .zero)
        view.text = text
        return view
    }

    func updateNSView(_ nsView: GitHubContributionTooltipNSView, context: Context) {
        nsView.text = text
    }
}

private final class GitHubContributionTooltipNSView: NSView {
    var text = ""
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        guard TooltipManager.shared.canShow, let window, window.isVisible else { return }
        let cursorRect = NSRect(origin: event.locationInWindow, size: .zero)
        let cursorPoint = window.convertToScreen(cursorRect).origin
        TooltipManager.shared.show(text: text, near: cursorPoint)
    }

    override func mouseExited(with event: NSEvent) {
        TooltipManager.shared.hide()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { TooltipManager.shared.hide() }
        super.viewWillMove(toWindow: newWindow)
    }
}

@MainActor
final class GitHubContributionsService: ObservableObject {
    static let refreshInterval: Duration = .seconds(30 * 60)

    struct Day: Identifiable {
        let date: Date
        let dateString: String
        let level: Int
        let count: Int

        var id: String { dateString }
        var tooltip: String {
            let day = GitHubContributionsService.calendar.component(.day, from: date)
            let dateLabel = GitHubContributionsService.tooltipDateFormatter.string(from: date)
                + GitHubContributionsService.ordinalSuffix(for: day)
            if count == 0 { return "No contributions on \(dateLabel)." }
            return "\(count) \(count == 1 ? "contribution" : "contributions") on \(dateLabel)."
        }
    }

    struct Week: Identifiable {
        let days: [Day]
        var id: String { days.first?.dateString ?? UUID().uuidString }
    }

    struct MonthMarker: Identifiable {
        let weekIndex: Int
        let title: String
        var id: Int { weekIndex }
    }

    @Published private(set) var weeks: [Week] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var loadedUsername = ""
    private var loadedAt: Date?

    var totalCount: Int {
        let today = Self.calendar.startOfDay(for: Date())
        let firstDay = Self.calendar.date(byAdding: .day, value: -364, to: today)!
        return weeks
            .flatMap(\.days)
            .filter { $0.date >= firstDay && $0.date <= today }
            .reduce(0) { $0 + $1.count }
    }

    var visibleWeeks: [Week] { Array(weeks.suffix(13)) }

    var visibleMonthMarkers: [MonthMarker] {
        var previousMonth: Int?
        let markers = visibleWeeks.enumerated().compactMap { index, week -> MonthMarker? in
            guard let firstDay = week.days.first else { return nil }
            let month = Self.calendar.component(.month, from: firstDay.date)
            defer { previousMonth = month }
            guard month != previousMonth else { return nil }
            return MonthMarker(weekIndex: index, title: Self.monthFormatter.string(from: firstDay.date))
        }

        return markers.enumerated().compactMap { index, marker in
            guard index + 1 < markers.count else { return marker }
            return markers[index + 1].weekIndex - marker.weekIndex < 3 ? nil : marker
        }
    }

    func load(username rawUsername: String) async {
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(username: username) else {
            weeks = []
            errorMessage = username.isEmpty ? nil : "Invalid GitHub username"
            return
        }

        if loadedUsername.caseInsensitiveCompare(username) == .orderedSame,
           let loadedAt,
           Date().timeIntervalSince(loadedAt) < 30 * 60 {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let range = Self.visibleDateRange()
        let urls = Self.contributionsURLs(username: username, range: range)
        guard !urls.isEmpty else {
            errorMessage = "Unable to load contributions"
            return
        }

        do {
            var contributions: [String: ContributionValue] = [:]
            for url in urls {
                var request = URLRequest(url: url)
                request.setValue("BangBar", forHTTPHeaderField: "User-Agent")
                request.setValue("text/html", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let html = String(data: data, encoding: .utf8) else {
                    throw URLError(.badServerResponse)
                }
                contributions.merge(Self.parseContributions(from: html)) { _, latest in latest }
            }

            guard !contributions.isEmpty else {
                throw URLError(.cannotParseResponse)
            }
            weeks = Self.makeWeeks(range: range, contributions: contributions)
            loadedUsername = username
            loadedAt = Date()
        } catch {
            weeks = []
            errorMessage = "GitHub is unavailable"
        }
    }

    fileprivate static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    fileprivate static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d"
        return formatter
    }()

    private static func visibleDateRange() -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: Date())
        let weekdayOffset = calendar.component(.weekday, from: today) - 1
        let currentWeekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today)!
        let start = calendar.date(byAdding: .weekOfYear, value: -52, to: currentWeekStart)!
        let end = calendar.date(byAdding: .day, value: 6, to: currentWeekStart)!
        return start...end
    }

    private static func contributionsURLs(
        username: String,
        range: ClosedRange<Date>
    ) -> [URL] {
        let startYear = calendar.component(.year, from: range.lowerBound)
        let endYear = calendar.component(.year, from: min(range.upperBound, Date()))

        return (startYear...endYear).compactMap { year in
            var components = URLComponents()
            components.scheme = "https"
            components.host = "github.com"
            components.path = "/users/\(username)/contributions"
            components.queryItems = [
                URLQueryItem(name: "from", value: String(format: "%04d-01-01", year)),
                URLQueryItem(name: "to", value: String(format: "%04d-12-31", year))
            ]
            return components.url
        }
    }

    private struct ContributionValue {
        let level: Int
        let count: Int
    }

    private static func parseContributions(from html: String) -> [String: ContributionValue] {
        let tagPattern = #"<[^>]+data-date="\d{4}-\d{2}-\d{2}"[^>]*>"#
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern) else { return [:] }
        let range = NSRange(html.startIndex..., in: html)
        var dateByElementID: [String: String] = [:]
        var levelByDate: [String: Int] = [:]

        for match in tagRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let date = attribute("data-date", in: tag),
                  let elementID = attribute("id", in: tag),
                  let rawLevel = attribute("data-level", in: tag),
                  let level = Int(rawLevel) else { continue }
            dateByElementID[elementID] = date
            levelByDate[date] = level
        }

        var countByDate: [String: Int] = [:]
        let tooltipPattern = #"<tool-tip[^>]+for="([^"]+)"[^>]*>([^<]+)</tool-tip>"#
        if let tooltipRegex = try? NSRegularExpression(pattern: tooltipPattern) {
            for match in tooltipRegex.matches(in: html, range: range) {
                guard match.numberOfRanges > 2,
                      let idRange = Range(match.range(at: 1), in: html),
                      let textRange = Range(match.range(at: 2), in: html),
                      let date = dateByElementID[String(html[idRange])] else { continue }
                let text = String(html[textRange])
                countByDate[date] = Int(text.prefix { $0.isNumber }) ?? 0
            }
        }

        var result: [String: ContributionValue] = [:]
        for (date, level) in levelByDate {
            result[date] = ContributionValue(level: level, count: countByDate[date] ?? 0)
        }
        return result
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[valueRange])
    }

    private static func makeWeeks(
        range: ClosedRange<Date>,
        contributions: [String: ContributionValue]
    ) -> [Week] {
        var result: [Week] = []
        var weekStart = range.lowerBound

        while weekStart <= range.upperBound {
            let days = (0..<7).compactMap { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
                let dateString = dateFormatter.string(from: date)
                let contribution = contributions[dateString]
                return Day(
                    date: date,
                    dateString: dateString,
                    level: contribution?.level ?? 0,
                    count: contribution?.count ?? 0
                )
            }
            result.append(Week(days: days))
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = nextWeek
        }
        return result
    }

    private static func isValid(username: String) -> Bool {
        username.range(of: #"^(?!-)[A-Za-z0-9-]{1,39}(?<!-)$"#, options: .regularExpression) != nil
    }

    fileprivate static func ordinalSuffix(for day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
