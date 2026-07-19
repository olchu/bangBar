import SwiftUI
import Combine
import AppKit

enum PanelLayout {
    // Меняйте это значение, чтобы регулировать высоту закреплённого верхнего бара.
    static let topBarHeight: CGFloat = 24
    static let topBarHorizontalPadding: CGFloat = 52
    static let notchContentClearance: CGFloat = 4
    static var expandedContentHeight: CGFloat {
        nowPlayingWidgetHeight + expandedVisibleEdgePadding
    }
    static func topSafeInset(on screen: NSScreen) -> CGFloat {
        guard screen.auxiliaryTopLeftArea != nil,
              screen.auxiliaryTopRightArea != nil else {
            return topBarHeight
        }

        let notchHeight = screen.auxiliaryTopLeftArea?.height ?? topBarHeight
        return max(topBarHeight, notchHeight + notchContentClearance)
    }

    static func expandedHeight(on screen: NSScreen) -> CGFloat {
        topSafeInset(on: screen) + expandedContentHeight
    }
    static let panelTopRadius: CGFloat = 22
    static let panelTopEarInset: CGFloat = 22
    static let compactMinimumWidth: CGFloat = 320
    static let compactNotchSidePadding: CGFloat = 100
    static let compactMaximumWidth: CGFloat = 360
    static let expandedVisibleEdgePadding: CGFloat = 20
    static let expandedHorizontalPadding: CGFloat = panelTopEarInset + panelTopRadius + expandedVisibleEdgePadding
    static let expandedWidgetSpacing: CGFloat = 20
    static let expandedDividerWidth: CGFloat = 1
    static let expandedDividerHeight: CGFloat = 60

    static let nowPlayingWidgetWidth: CGFloat = 300
    static let nowPlayingWidgetHeight: CGFloat = 110
    static let nowPlayingArtworkSize: CGFloat = 110
    static let mirrorWidgetWidth: CGFloat = 94
    static let mirrorWidgetHeight: CGFloat = 94
    static let systemWidgetWidth: CGFloat = 160
    static let clockWidgetWidth: CGFloat = 190
    static let moonWidgetWidth: CGFloat = 110
    static let pomodoroWidgetWidth: CGFloat = 110
    static let remindersWidgetWidth: CGFloat = 130
    static let calendarWidgetWidth: CGFloat = 140
    static let emptyWidgetWidth: CGFloat = 220

    static var expandedWidgetWidths: [CGFloat] {
        expandedWidgetWidths(
            showNowPlaying: BangBarSettings.showNowPlayingWidget,
            showClock: BangBarSettings.showClockWidget,
            showMoon: BangBarSettings.showMoonWidget,
            showPomodoro: BangBarSettings.showPomodoroWidget,
            showReminders: BangBarSettings.showRemindersWidget,
            showMirror: BangBarSettings.showMirrorWidget,
            showSystem: BangBarSettings.showSystemWidget
        )
    }

    static var expandedWidth: CGFloat {
        expandedWidth(
            showNowPlaying: BangBarSettings.showNowPlayingWidget,
            showClock: BangBarSettings.showClockWidget,
            showMoon: BangBarSettings.showMoonWidget,
            showPomodoro: BangBarSettings.showPomodoroWidget,
            showReminders: BangBarSettings.showRemindersWidget,
            showMirror: BangBarSettings.showMirrorWidget,
            showSystem: BangBarSettings.showSystemWidget
        )
    }

    static func expandedWidgetWidths(
        showNowPlaying: Bool,
        showClock: Bool,
        showMoon: Bool,
        showPomodoro: Bool,
        showReminders: Bool,
        showMirror: Bool,
        showSystem: Bool
    ) -> [CGFloat] {
        var widths: [CGFloat] = []

        if showNowPlaying { widths.append(nowPlayingWidgetWidth) }
        if showClock { widths.append(clockWidgetWidth) }
        if showMoon { widths.append(moonWidgetWidth) }
        if showPomodoro { widths.append(pomodoroWidgetWidth) }
        if showReminders { widths.append(remindersWidgetWidth) }
        if showMirror { widths.append(mirrorWidgetWidth) }
        if showSystem { widths.append(systemWidgetWidth) }

        guard !widths.isEmpty else { return [emptyWidgetWidth] }

        return widths.enumerated().flatMap { index, width in
            index == 0 ? [width] : [expandedDividerWidth, width]
        }
    }

    static func expandedWidth(
        showNowPlaying: Bool,
        showClock: Bool,
        showMoon: Bool,
        showPomodoro: Bool,
        showReminders: Bool,
        showMirror: Bool,
        showSystem: Bool
    ) -> CGFloat {
        let widths = expandedWidgetWidths(
            showNowPlaying: showNowPlaying,
            showClock: showClock,
            showMoon: showMoon,
            showPomodoro: showPomodoro,
            showReminders: showReminders,
            showMirror: showMirror,
            showSystem: showSystem
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
        case clipboardGroup
    }

    @Published var isExpanded = false
    @Published var isCompact = false
    @Published var compactContent: CompactContent = .nowPlaying
    @Published var contentVisible = false
    @Published var compactArtworkRevealAllowed = true
    @Published var compactIndicatorRevealAllowed = true
    @Published var compactArtworkRevealAnimated = true
    @Published var artworkHeroProgress: CGFloat?
    @Published var showsClipboardHistory = false
    @Published var clipboardFilter: ClipboardHistoryFilter = .all
    @Published var topSafeInset = PanelLayout.topBarHeight
}
