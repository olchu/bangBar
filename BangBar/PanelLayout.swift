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
        guard let notch = notchRect(on: screen) else { return topBarHeight }
        return max(topBarHeight, notch.height + notchContentClearance)
    }

    /// The camera housing in screen coordinates; nil on displays without a notch.
    static func notchRect(on screen: NSScreen?) -> NSRect? {
        guard let screen,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return nil }
        return NSRect(
            x: leftArea.maxX,
            y: screen.frame.maxY - leftArea.height,
            width: max(rightArea.minX - leftArea.maxX, 0),
            height: leftArea.height
        )
    }

    static func notchWidth(on screen: NSScreen?) -> CGFloat {
        notchRect(on: screen)?.width ?? 0
    }

    /// A frame of the given size centered on the screen and pinned to its top edge, like every panel state.
    /// Shared by compact artwork and the clipboard preview; the artwork hero animation starts from exactly this frame.
    static func compactArtworkSize(forHeight height: CGFloat) -> CGFloat {
        min(max(height - 10, 22), 32)
    }

    static func compactArtworkCornerRadius(forSize size: CGFloat) -> CGFloat {
        min(7, size / 4)
    }

    static func topCenteredFrame(width: CGFloat, height: CGFloat, on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
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
    static let expandedWidgetSpacing: CGFloat = 12
    static let expandedDividerWidth: CGFloat = 1
    static let expandedDividerHeight: CGFloat = 60
    /// The width occupied by the original seven-widget layout. New widgets must fit this budget.
    static let maximumExpandedWidth: CGFloat = 1468
    static let expandedScreenEdgeInset: CGFloat = 8

    static let nowPlayingWidgetWidth: CGFloat = 300
    static let nowPlayingWidgetHeight: CGFloat = 110
    static let nowPlayingArtworkSize: CGFloat = 110
    static let mirrorWidgetWidth: CGFloat = 94
    static let mirrorWidgetHeight: CGFloat = 94
    static let systemWidgetWidth: CGFloat = 160
    static let githubWidgetWidth: CGFloat = 150
    static let aiUsageWidgetWidth: CGFloat = 170
    static let companionWidgetWidth: CGFloat = 170
    static let habitsWidgetWidth: CGFloat = 220
    static let translatorWidgetWidth: CGFloat = 150
    static let dayPlansWidgetWidth: CGFloat = 170
    static let clockWidgetWidth: CGFloat = 194
    static let moonWidgetWidth: CGFloat = 110
    static let pomodoroWidgetWidth: CGFloat = 110
    static let countdownWidgetWidth: CGFloat = 150
    static let remindersWidgetWidth: CGFloat = 130
    static let emptyWidgetWidth: CGFloat = 220

    static var enabledWidgets: [BangBarWidget] {
        BangBarSettings.widgetOrder(
            from: UserDefaults.standard.string(forKey: BangBarSettings.Key.widgetOrder)
                ?? BangBarSettings.defaultWidgetOrderRaw
        )
        .filter { BangBarSettings.isWidgetVisible($0) }
    }

    static func maximumExpandedWidth(on screen: NSScreen?) -> CGFloat {
        guard let screen else { return maximumExpandedWidth }
        return min(maximumExpandedWidth, screen.visibleFrame.width - expandedScreenEdgeInset * 2)
    }

    static func enabledWidgets(forPage page: Int) -> [BangBarWidget] {
        let pages = BangBarSettings.widgetPages(
            from: UserDefaults.standard.string(forKey: BangBarSettings.Key.widgetPages) ?? "{}"
        )
        return enabledWidgets.filter { (pages[$0.rawValue] ?? 0) == page }
    }

    static func fittedWidgets(forPage page: Int, on screen: NSScreen?) -> [BangBarWidget] {
        widgetsThatFit(enabledWidgets(forPage: page), maximumWidth: maximumExpandedWidth(on: screen))
    }

    static func expandedWidth(forPage page: Int, on screen: NSScreen?) -> CGFloat {
        expandedWidth(for: fittedWidgets(forPage: page, on: screen))
    }

    static func expandedWidth(for widgets: [BangBarWidget]) -> CGFloat {
        guard !widgets.isEmpty else {
            return expandedHorizontalPadding * 2 + emptyWidgetWidth
        }

        let widgetWidth = widgets.reduce(0) { $0 + $1.layoutWidth }
        let dividerCount = CGFloat(widgets.count - 1)
        let elementSpacingCount = dividerCount * 2
        return expandedHorizontalPadding * 2
            + widgetWidth
            + dividerCount * expandedDividerWidth
            + elementSpacingCount * expandedWidgetSpacing
    }

    static func widgetsThatFit(
        _ widgets: [BangBarWidget],
        maximumWidth: CGFloat
    ) -> [BangBarWidget] {
        var result: [BangBarWidget] = []
        for widget in widgets where expandedWidth(for: result + [widget]) <= maximumWidth {
            result.append(widget)
        }
        return result
    }

    static let compactHorizontalPadding: CGFloat = 50

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
    @Published var currentPage = 0
}

extension NSScreen {
    /// The screen under `point` (in global coordinates), falling back to the main screen.
    static func containing(_ point: NSPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) } ?? main
    }
}
