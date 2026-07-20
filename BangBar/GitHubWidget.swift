import Combine
import Foundation
import SwiftUI

struct GitHubWidget: View {
    static let horizontalOverflow: CGFloat = 12

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @AppStorage(BangBarSettings.Key.githubUsername) private var username = ""
    @StateObject private var contributions = GitHubContributionsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text("GITHUB")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))

                Spacer(minLength: 4)

                Text(summaryLabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState("Add username in Settings")
            } else if let errorMessage = contributions.errorMessage {
                emptyState(errorMessage)
            } else {
                contributionGrid
                    .opacity(contributions.isLoading && contributions.weeks.isEmpty ? 0.35 : 1)
            }
        }
        .frame(
            width: PanelLayout.githubWidgetWidth + Self.horizontalOverflow * 2,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .task(id: username) {
            await contributions.load(username: username)
        }
    }

    private var accentColor: Color { Color(hex: accentColorHex) }

    private var summaryLabel: String {
        guard !contributions.weeks.isEmpty else { return "4 MONTHS" }
        return "\(contributions.totalCount) CONTRIBUTIONS"
    }

    private var contributionGrid: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Color.clear
                    .frame(width: 18, height: 1)

                ZStack(alignment: .topLeading) {
                    ForEach(contributions.monthMarkers) { marker in
                        Text(marker.title)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                            .offset(x: CGFloat(marker.weekIndex) * 10)
                    }
                }
                .frame(width: 167, height: 9, alignment: .leading)
            }

            HStack(spacing: 5) {
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        Text(weekdayLabel(for: dayIndex))
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                            .frame(width: 18, height: 7, alignment: .leading)
                    }
                }

                HStack(spacing: 3) {
                    ForEach(contributions.weeks) { week in
                        VStack(spacing: 3) {
                            ForEach(week.days) { day in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(color(for: day.level))
                                    .frame(width: 7, height: 7)
                                    .help(day.tooltip)
                            }
                        }
                    }
                }
            }
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

    private func color(for level: Int) -> Color {
        switch level {
        case 1: accentColor.opacity(0.24)
        case 2: accentColor.opacity(0.46)
        case 3: accentColor.opacity(0.72)
        case 4...: accentColor
        default: Color.white.opacity(0.06)
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

@MainActor
private final class GitHubContributionsService: ObservableObject {
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
        weeks.flatMap(\.days).reduce(0) { $0 + $1.count }
    }

    var monthMarkers: [MonthMarker] {
        var previousMonth: Int?
        let markers = weeks.enumerated().compactMap { index, week -> MonthMarker? in
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
           Date().timeIntervalSince(loadedAt) < 3 * 60 * 60 {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let range = Self.visibleDateRange()
        guard let url = Self.contributionsURL(username: username, range: range) else {
            errorMessage = "Unable to load contributions"
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("BangBar", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }

            let contributions = Self.parseContributions(from: html)
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
        let start = calendar.date(byAdding: .weekOfYear, value: -16, to: currentWeekStart)!
        let end = calendar.date(byAdding: .day, value: 6, to: currentWeekStart)!
        return start...end
    }

    private static func contributionsURL(
        username: String,
        range: ClosedRange<Date>
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/users/\(username)/contributions"
        components.queryItems = [
            URLQueryItem(name: "from", value: dateFormatter.string(from: range.lowerBound)),
            URLQueryItem(name: "to", value: dateFormatter.string(from: min(range.upperBound, Date())))
        ]
        return components.url
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
