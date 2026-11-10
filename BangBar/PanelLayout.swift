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

    /// The expanded panel's SwiftUI content is drawn at this scale, anchored to the top edge.
    static let expandedPanelScale: CGFloat = 0.955
    static let expansionSpring = Animation.spring(response: 0.35, dampingFraction: 0.66)
    /// How fast the panel's content (and the AppKit terminal with it) fades when the panel closes.
    static let contentFadeDuration: TimeInterval = 0.1
    /// The hidden panel's scale where there is no notch to collapse into.
    static let hiddenPanelScale: CGFloat = 0.22
    static let collapseAnimation = Animation.easeInOut(duration: 0.22)
    static let collapseFadeAnimation = Animation.easeIn(duration: 0.08).delay(0.16)
    /// AppKit content over the panel (the terminal) waits this long for `expansionSpring` to settle.
    static let expansionSpringSettleDelay: TimeInterval = 0.3

    static let terminalDefaultWidth = 860
    static let terminalDefaultMaxLines = 17
    static let terminalMaxLinesOptions = [1, 2, 3, 5, 8, 10, 12, 15, 17, 20, 25, 30]
    static let terminalInset: CGFloat = 16

    /// The width from Settings, never narrower than the widget page it opens from nor wider than the screen allows.
    static func terminalWidth(forPage page: Int, on screen: NSScreen?) -> CGFloat {
        let preferred = CGFloat(UserDefaults.standard.integer(forKey: BangBarSettings.Key.terminalWidth))
        return min(max(expandedWidth(forPage: page, on: screen), preferred), maximumExpandedWidth(on: screen))
    }

    static var terminalMaxLines: Int {
        let lines = UserDefaults.standard.integer(forKey: BangBarSettings.Key.terminalMaxLines)
        return lines > 0 ? lines : terminalDefaultMaxLines
    }

    /// The panel height whose `terminalContentRect` is `containerHeight` tall.
    static func terminalPanelHeight(containerHeight: CGFloat, topSafeInset: CGFloat) -> CGFloat {
        (containerHeight / expandedPanelScale + terminalInset + topSafeInset + 2).rounded(.up)
    }

    /// The terminal's rect in a panel of `size`, with a top-left origin. AppKit content is not scaled with the
    /// SwiftUI panel, so the rect follows the scaled `NotchPanelShape`: below the top bar, inside the ears and
    /// the bottom corners.
    static func terminalContentRect(in size: CGSize, topSafeInset: CGFloat) -> CGRect {
        let scale = expandedPanelScale
        let shapeMinX = size.width * (1 - scale) / 2
        let sideInset = (panelTopEarInset + panelTopRadius + terminalInset) * scale
        let top = (topSafeInset + 2) * scale
        let bottom = (size.height - terminalInset) * scale
        return CGRect(
            x: shapeMinX + sideInset,
            y: top,
            width: max(size.width * scale - sideInset * 2, 0),
            height: max(bottom - top, 0)
        ).integral
    }

    static let compactHorizontalPadding: CGFloat = 50
    /// The compact strip's content leaves this fast when a notice beside the notch takes its place; the notice
    /// waits exactly this long before growing over the strip.
    static let compactContentExitDuration: TimeInterval = 0.08

    static func compactWidth(for notchWidth: CGFloat) -> CGFloat {
        min(max(notchWidth + compactNotchSidePadding * 2, compactMinimumWidth), compactMaximumWidth)
    }

    static func compactWidth(on screen: NSScreen) -> CGFloat {
        notchRect(on: screen).map { compactWidth(for: $0.width) } ?? compactMinimumWidth
    }

    static func compactHeight(on screen: NSScreen) -> CGFloat {
        notchRect(on: screen)?.height ?? NSStatusBar.system.thickness
    }

    /// Hidden behind the notch; the compact strip grows out of this and shrinks back into it.
    static func concealedCompactWidth(on screen: NSScreen) -> CGFloat {
        guard let notch = notchRect(on: screen) else { return 1 }
        return max(notch.width - 8, 1)
    }
}

/// Panel-level surfaces, stacked vertically: Terminal ↑ Widgets ↓ Clipboard.
enum PanelSurface {
    case widgets
    case clipboard
    case terminal
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
    /// A notice beside the notch is showing in the compact strip's place.
    @Published var compactContentCovered = false
    @Published var surface = PanelSurface.widgets
    /// The scale of the hidden panel: the notch's width, so a collapse ends inside the notch.
    @Published var collapsedScale = PanelLayout.hiddenPanelScale
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

extension View {
    /// Scales up from `hiddenScale` and fades in when shown; leaves faster than it arrives.
    func focusReveal(isShown: Bool, hiddenScale: CGFloat, delay: TimeInterval = 0, exitDuration: TimeInterval = 0.1) -> some View {
        scaleEffect(isShown ? 1 : hiddenScale)
            .opacity(isShown ? 1 : 0)
            .animation(
                isShown ? .spring(response: 0.34, dampingFraction: 0.8).delay(delay) : .easeIn(duration: exitDuration),
                value: isShown
            )
    }
}
