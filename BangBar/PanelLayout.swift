import SwiftUI
import Combine

enum PanelLayout {
    static let expandedHeight: CGFloat = 155
    static let panelTopRadius: CGFloat = 22
    static let panelTopEarInset: CGFloat = 22
    static let compactMinimumWidth: CGFloat = 320
    static let compactNotchSidePadding: CGFloat = 100
    static let compactMaximumWidth: CGFloat = 360
    static let expandedVisibleEdgePadding: CGFloat = 20
    static let expandedHorizontalPadding: CGFloat = panelTopEarInset + panelTopRadius + expandedVisibleEdgePadding
    static let expandedWidgetSpacing: CGFloat = 20
    static let expandedDividerWidth: CGFloat = 1
    static let expandedDividerHeight: CGFloat = 70

    static let nowPlayingWidgetWidth: CGFloat = 300
    static let nowPlayingWidgetHeight: CGFloat = 110
    static let nowPlayingArtworkSize: CGFloat = 110
    static let mirrorWidgetWidth: CGFloat = 94
    static let mirrorWidgetHeight: CGFloat = 94
    static let clockWidgetWidth: CGFloat = 190
    static let pomodoroWidgetWidth: CGFloat = 110
    static let calendarWidgetWidth: CGFloat = 140
    static let emptyWidgetWidth: CGFloat = 220

    static var expandedWidgetWidths: [CGFloat] {
        expandedWidgetWidths(
            showNowPlaying: BangBarSettings.showNowPlayingWidget,
            showClock: BangBarSettings.showClockWidget,
            showPomodoro: BangBarSettings.showPomodoroWidget,
            showMirror: BangBarSettings.showMirrorWidget
        )
    }

    static var expandedWidth: CGFloat {
        expandedWidth(
            showNowPlaying: BangBarSettings.showNowPlayingWidget,
            showClock: BangBarSettings.showClockWidget,
            showPomodoro: BangBarSettings.showPomodoroWidget,
            showMirror: BangBarSettings.showMirrorWidget
        )
    }

    static func expandedWidgetWidths(
        showNowPlaying: Bool,
        showClock: Bool,
        showPomodoro: Bool,
        showMirror: Bool
    ) -> [CGFloat] {
        var widths: [CGFloat] = []

        if showNowPlaying { widths.append(nowPlayingWidgetWidth) }
        if showClock { widths.append(clockWidgetWidth) }
        if showPomodoro { widths.append(pomodoroWidgetWidth) }
        if showMirror { widths.append(mirrorWidgetWidth) }

        guard !widths.isEmpty else { return [emptyWidgetWidth] }

        return widths.enumerated().flatMap { index, width in
            index == 0 ? [width] : [expandedDividerWidth, width]
        }
    }

    static func expandedWidth(
        showNowPlaying: Bool,
        showClock: Bool,
        showPomodoro: Bool,
        showMirror: Bool
    ) -> CGFloat {
        let widths = expandedWidgetWidths(
            showNowPlaying: showNowPlaying,
            showClock: showClock,
            showPomodoro: showPomodoro,
            showMirror: showMirror
        )
        let contentWidth = widths.reduce(0, +)
        let spacingWidth = expandedWidgetSpacing * CGFloat(max(widths.count - 1, 0))
        return expandedHorizontalPadding * 2 + contentWidth + spacingWidth
    }

    static func compactHorizontalPadding(for height: CGFloat) -> CGFloat {
        min(max(height + 18, 50), 50)
    }

    static func compactWidth(for notchWidth: CGFloat) -> CGFloat {
        min(max(notchWidth + compactNotchSidePadding * 2, compactMinimumWidth), compactMaximumWidth)
    }
}

final class PanelState: ObservableObject {
    enum CompactContent {
        case nowPlaying
        case pomodoro
    }

    @Published var isExpanded = false
    @Published var isCompact = false
    @Published var compactContent: CompactContent = .nowPlaying
    @Published var contentVisible = false
    @Published var compactArtworkRevealAllowed = true
    @Published var compactIndicatorRevealAllowed = true
    @Published var compactArtworkRevealAnimated = true
    @Published var artworkHeroProgress: CGFloat?
}
