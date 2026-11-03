import AppKit
import Combine
import SwiftUI

enum NotchNotice {
    /// Hangs at `geometry`: next to the caret, or below the notch when the caret is unknown.
    case layoutSwitch(original: String, replacement: String, geometry: NotchNoticeGeometry)
    case activity(LiveActivity)
    case volume(level: Float, isMuted: Bool)

    var visibleDuration: TimeInterval {
        switch self {
        case .layoutSwitch: 1.8
        case .activity: 2.4
        case .volume: 1.5
        }
    }

    var isLayoutSwitch: Bool {
        if case .layoutSwitch = self { return true }
        return false
    }
}

/// What a notice beside the notch shows: a symbol left of the notch, a value right of it and a footer under it.
struct StripNotice: Equatable {
    enum Footer: Equatable {
        case title(String)
        case level(Float)
    }

    let symbol: String
    let value: String
    let footer: Footer
    /// The wider of the symbol and the value, which sets how far the strip reaches past the notch.
    let sideContentWidth: CGFloat

    init(_ activity: LiveActivity) {
        symbol = activity.symbol
        value = activity.detail
        footer = .title(activity.title)
        sideContentWidth = Self.sideContentWidth(for: activity.detail)
    }

    init(volume: Float, isMuted: Bool) {
        let level = isMuted ? 0 : volume
        symbol = switch level {
        case ...0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
        value = "\(Int((level * 100).rounded()))%"
        footer = .level(level)
        sideContentWidth = Self.volumeSideContentWidth
    }

    /// Sized for "100%" so the strip keeps its width while the level changes; held keys rebuild this many times a second.
    private static let volumeSideContentWidth = sideContentWidth(for: "100%")

    private static func sideContentWidth(for value: String) -> CGFloat {
        let textWidth = (value as NSString).size(withAttributes: [.font: NotchStripGeometry.sideFont]).width.rounded(.up)
        return max(textWidth, NotchStripGeometry.symbolWidth)
    }
}

private enum NotchNoticePresentation: Equatable {
    case below(NotchNoticeGeometry, original: String, replacement: String)
    case beside(NotchStripGeometry, StripNotice)

    var windowFrame: NSRect {
        switch self {
        case .below(let geometry, _, _): geometry.windowFrame
        case .beside(let geometry, _): geometry.windowFrame
        }
    }

    var growsFromStrip: Bool {
        if case .beside(let geometry, _) = self { return geometry.growsFromStrip }
        return false
    }

    /// Notices with the same shape only swap their content, without growing out of the notch again.
    func hasSameShape(as other: Self?) -> Bool {
        switch (self, other) {
        case let (.below(geometry, _, _), .below(otherGeometry, _, _)?): geometry == otherGeometry
        case let (.beside(geometry, _), .beside(otherGeometry, _)?): geometry == otherGeometry
        default: false
        }
    }
}

/// The one channel for notices that grow out of the notch: a new notice replaces the visible one, and none is
/// shown while `isSuppressed` (the expanded panel already shows the same information). A separate click-through
/// window, so a notice never takes part in the hover panel's lifecycle.
final class NotchNoticeCenter {
    private static let hideAnimationDuration: TimeInterval = 0.16
    private static let revealAnimation = Animation.spring(response: 0.36, dampingFraction: 0.76)

    var isSuppressed: () -> Bool = { false }
    var compactPanelFrame: () -> NSRect? = { nil }
    /// Hides the compact strip's artwork and indicator while a notice takes their places, and brings them back.
    var setCompactStripCovered: (Bool) -> Void = { _ in }
    private let state = NotchNoticeState()
    private var currentNotice: NotchNotice?
    private lazy var window = makeWindow()
    private var coversStrip = false
    private var revealWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?
    private var orderOutWorkItem: DispatchWorkItem?

    func present(_ notice: NotchNotice, overridesSuppression: Bool = false) {
        guard overridesSuppression || !isSuppressed(), let presentation = presentation(for: notice) else { return }
        orderOutWorkItem?.cancel()
        currentNotice = notice
        let isShapeChange = !presentation.hasSameShape(as: state.presentation)
        // Also while the previous notice is still shrinking, so it reshapes into the new one instead of jumping.
        if isShapeChange, window.isVisible {
            window.setFrame(presentation.windowFrame, display: true)
            withAnimation(Self.revealAnimation) {
                state.presentation = presentation
            }
        } else {
            // Held volume keys update the visible notice many times a second, and a reveal waiting for the strip
            // shows the latest notice; only the content changes then.
            state.presentation = presentation
        }
        if coversStrip, !presentation.growsFromStrip {
            coverStrip(false)
        }
        if !state.isRevealed, revealWorkItem == nil {
            // Over the compact strip its artwork and indicator leave first, so they never show through.
            if presentation.growsFromStrip, !coversStrip {
                coverStrip(true)
                let reveal = DispatchWorkItem { [weak self] in self?.reveal() }
                revealWorkItem = reveal
                DispatchQueue.main.asyncAfter(deadline: .now() + PanelLayout.compactContentExitDuration, execute: reveal)
            } else {
                reveal()
            }
        }

        hideWorkItem?.cancel()
        let hide = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + notice.visibleDuration, execute: hide)
    }

    func dismiss(where matches: (NotchNotice) -> Bool = { _ in true }) {
        guard let notice = currentNotice, matches(notice) else { return }
        hideWorkItem?.cancel()
        if let revealWorkItem {
            revealWorkItem.cancel()
            self.revealWorkItem = nil
            finishHiding()
            return
        }
        guard state.isRevealed else { return }
        // The strip may have appeared or gone while the notice was up; it shrinks into whatever is there now.
        if case .beside(var geometry, let content) = state.presentation {
            geometry.conceal(into: compactPanelFrame())
            state.presentation = .beside(geometry, content)
            if geometry.growsFromStrip, !coversStrip {
                coverStrip(true)
            }
        }
        withAnimation(.easeInOut(duration: Self.hideAnimationDuration)) {
            state.isRevealed = false
        }
        let orderOut = DispatchWorkItem { [weak self] in self?.finishHiding() }
        orderOutWorkItem = orderOut
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideAnimationDuration, execute: orderOut)
    }

    /// Orders the window in with the concealed shape drawn, then grows it on the next pass, so even the first
    /// notice has a shape to grow from. Both steps stay cancellable through `revealWorkItem`.
    private func reveal() {
        guard let presentation = state.presentation else { return }
        window.setFrame(presentation.windowFrame, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.orderFrontRegardless()
        let grow = DispatchWorkItem { [weak self] in
            guard let self else { return }
            revealWorkItem = nil
            withAnimation(Self.revealAnimation) {
                self.state.isRevealed = true
            }
        }
        revealWorkItem = grow
        DispatchQueue.main.async(execute: grow)
    }

    private func finishHiding() {
        window.orderOut(nil)
        if coversStrip {
            coverStrip(false)
        }
    }

    private func coverStrip(_ covers: Bool) {
        coversStrip = covers
        setCompactStripCovered(covers)
    }

    /// A layout switch hangs at its own geometry; every other notice sits beside the notch, growing out of the
    /// compact strip when that is shown.
    private func presentation(for notice: NotchNotice) -> NotchNoticePresentation? {
        let content: StripNotice
        switch notice {
        case .layoutSwitch(let original, let replacement, let geometry):
            return .below(geometry, original: original, replacement: replacement)
        case .activity(let activity):
            content = StripNotice(activity)
        case .volume(let level, let isMuted):
            content = StripNotice(volume: level, isMuted: isMuted)
        }
        let strip = compactPanelFrame()
        guard let screen = strip.flatMap({ NSScreen.containing(NSPoint(x: $0.midX, y: $0.midY)) }) ?? Self.notchScreen
        else { return nil }
        return .beside(NotchStripGeometry(screen: screen, strip: strip, sideContentWidth: content.sideContentWidth), content)
    }

    private static var notchScreen: NSScreen? {
        NSScreen.screens.first { PanelLayout.notchRect(on: $0) != nil } ?? NSScreen.main
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: NotchNoticeView(state: state))
        return panel
    }
}

private final class NotchNoticeState: ObservableObject {
    @Published var presentation: NotchNoticePresentation?
    @Published var isRevealed = false
}

struct NotchNoticeGeometry: Equatable {
    static let bodyHeight: CGFloat = 30
    static let fillet: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    static let contentSpacing: CGFloat = 8
    static let arrowWidth: CGFloat = 10
    static let maximumBodyWidth: CGFloat = 300
    /// Without a notch the notice floats this far below the menu bar instead of growing out of it.
    static let menuBarGap: CGFloat = 6
    static let fieldGap: CGFloat = 6
    /// When only the caret's line is known, the gap also has to clear the field's own padding around the text.
    static let lineGap: CGFloat = 14
    /// Fields up to this tall (inputs, chat boxes) are cleared entirely; in taller editors only the caret's line is.
    static let maximumClearedFieldHeight: CGFloat = 120
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// The stem sits behind the physical notch; zero on displays without one.
    var stemWidth: CGFloat = 0
    var stemHeight: CGFloat = 0
    var bodyWidth: CGFloat = 0
    /// Next to the caret the body grows away from the text line, which is upward when it sits above the line.
    var growsUpward = false
    var windowFrame = NSRect.zero

    var size: CGSize {
        CGSize(width: max(bodyWidth, stemWidth + Self.fillet * 2), height: stemHeight + Self.bodyHeight)
    }

    /// Grows out of the notch (or floats below the menu bar) with a body sized for `contentWidth`.
    init(screen: NSScreen, contentWidth: CGFloat) {
        let notch = PanelLayout.notchRect(on: screen)
        stemWidth = notch?.width ?? 0
        stemHeight = notch?.height ?? NSStatusBar.system.thickness + Self.menuBarGap

        let minimumWidth = stemWidth > 0 ? stemWidth + (Self.fillet + Self.cornerRadius) * 2 : 0
        bodyWidth = min(max(contentWidth, minimumWidth), max(Self.maximumBodyWidth, minimumWidth))
        windowFrame = PanelLayout.topCenteredFrame(width: size.width, height: size.height, on: screen)
    }

    /// Above the caret's field (or just its line in a tall editor) with the replacement ending over the caret,
    /// or below it when there is no room above. nil when the caret is missing or off every screen.
    init?(caret: TextCaret?, contentWidth: CGFloat) {
        guard let caret, let primary = NSScreen.screens.first else { return nil }
        let toAppKit = { (rect: CGRect) in
            NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let line = toAppKit(caret.line)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: line.minX, y: line.midY)) })
        else { return nil }
        let field = caret.field.map(toAppKit).flatMap { field in
            field.height <= Self.maximumClearedFieldHeight
                && field.minY <= line.minY + 1 && field.maxY >= line.maxY - 1 ? field : nil
        }
        let cleared = field ?? line
        let gap = field == nil ? Self.lineGap : Self.fieldGap

        bodyWidth = min(contentWidth, Self.maximumBodyWidth)
        let visible = screen.visibleFrame
        let aboveY = cleared.maxY + gap
        growsUpward = aboveY + Self.bodyHeight <= visible.maxY
        let y = growsUpward ? aboveY : cleared.minY - gap - Self.bodyHeight
        let x = min(max(line.minX + Self.horizontalPadding - bodyWidth, visible.minX), visible.maxX - bodyWidth)
        windowFrame = NSRect(x: x, y: y, width: bodyWidth, height: Self.bodyHeight)
    }

    /// Body width for `original → replacement` on one line.
    static func contentWidth(original: String, replacement: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = [original, replacement].reduce(0) { $0 + ($1 as NSString).size(withAttributes: attributes).width }
        return (textWidth + arrowWidth + contentSpacing * 2 + horizontalPadding * 2).rounded(.up)
    }
}

/// Beside the notch: the compact strip's shape, widened to fit the side content, with a footer row under the notch.
struct NotchStripGeometry: Equatable {
    static let footerHeight: CGFloat = 18
    static let footerBottomInset: CGFloat = 4
    /// Matches the compact strip, so the symbol and the value take the places of its artwork and indicator.
    static let sidePadding = PanelLayout.compactHorizontalPadding
    static let notchGap: CGFloat = 8
    static let symbolWidth: CGFloat = 16
    static let volumeBarHeight: CGFloat = 5
    static let maximumWidth: CGFloat = 480
    static let sideFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    static let footerFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    /// Zero on displays without a notch; the sides then meet at the middle of a menu-bar-high strip.
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let size: CGSize
    let windowFrame: NSRect
    private let notchSize: CGSize
    private var stripSize: CGSize?

    /// At least as wide as the compact strip, so it covers the strip it grows out of.
    init(screen: NSScreen, strip: NSRect?, sideContentWidth: CGFloat) {
        notchWidth = PanelLayout.notchWidth(on: screen)
        notchHeight = PanelLayout.compactHeight(on: screen)
        notchSize = CGSize(width: PanelLayout.concealedCompactWidth(on: screen), height: notchHeight)
        let fittedWidth = notchWidth + (Self.sidePadding + sideContentWidth + Self.notchGap) * 2
        let width = min(max(fittedWidth, PanelLayout.compactWidth(on: screen), strip?.width ?? 0), Self.maximumWidth)
        size = CGSize(width: width.rounded(.up), height: notchHeight + Self.footerHeight)
        windowFrame = PanelLayout.topCenteredFrame(width: Self.maximumWidth, height: size.height, on: screen)
        stripSize = strip?.size
    }

    /// What the notice grows out of and shrinks back into: the compact strip when it is shown, otherwise the notch.
    var concealedSize: CGSize { stripSize ?? notchSize }
    var growsFromStrip: Bool { stripSize != nil }

    mutating func conceal(into strip: NSRect?) {
        stripSize = strip?.size
    }

    /// The compact strip's corners: its radii are clamped to half its height, which is the notch's.
    var shape: NotchPanelShape {
        NotchPanelShape(
            topRadius: min(PanelLayout.panelTopRadius, notchHeight / 2),
            bottomRadius: min(NotchPanelShape.defaultBottomRadius, notchHeight / 2)
        )
    }

    /// The room on each side between the strip's padding and the notch.
    var sideWidth: CGFloat {
        max((size.width - notchWidth) / 2 - Self.sidePadding - Self.notchGap, Self.symbolWidth)
    }

    var footerWidth: CGFloat {
        size.width - Self.sidePadding * 2
    }
}

private struct NotchNoticeView: View {
    @ObservedObject var state: NotchNoticeState
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    var body: some View {
        let accentColor = Color(hex: accentColorHex)
        switch state.presentation {
        case .below(let geometry, let original, let replacement):
            LayoutSwitchNoticeView(
                original: original,
                replacement: replacement,
                geometry: geometry,
                isRevealed: state.isRevealed,
                accentColor: accentColor
            )
        case .beside(let geometry, let content):
            StripNoticeView(content: content, geometry: geometry, isRevealed: state.isRevealed, accentColor: accentColor)
        case nil:
            EmptyView()
        }
    }
}

private struct LayoutSwitchNoticeView: View {
    let original: String
    let replacement: String
    let geometry: NotchNoticeGeometry
    let isRevealed: Bool
    let accentColor: Color

    var body: some View {
        let shape = NotchNoticeShape(geometry: geometry, progress: isRevealed ? 1 : 0)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            // Away from the notch the black body needs an edge to stand out against dark windows.
            if geometry.stemWidth == 0 {
                shape.stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .opacity(isRevealed ? 1 : 0)
            }

            HStack(spacing: NotchNoticeGeometry.contentSpacing) {
                Text(original)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .truncationMode(.middle)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: NotchNoticeGeometry.arrowWidth)
                Text(replacement)
                    .foregroundStyle(Color.white)
                    .truncationMode(.middle)
            }
            .font(Font(NotchNoticeGeometry.font))
            .lineLimit(1)
            .padding(.horizontal, NotchNoticeGeometry.horizontalPadding)
            .frame(width: geometry.bodyWidth, height: NotchNoticeGeometry.bodyHeight)
            .offset(y: geometry.stemHeight)
            .opacity(isRevealed ? 1 : 0)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
    }
}

private struct StripNoticeView: View {
    let content: StripNotice
    let geometry: NotchStripGeometry
    let isRevealed: Bool
    let accentColor: Color

    var body: some View {
        let shape = TopCenteredShape(base: geometry.shape, size: isRevealed ? geometry.size : geometry.concealedSize)
        ZStack(alignment: .top) {
            shape.fill(Color.black)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Image(systemName: content.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: NotchStripGeometry.symbolWidth, alignment: .leading)
                        .focusReveal(isShown: isRevealed, hiddenScale: 0.6, delay: 0.02)
                    Spacer(minLength: 0)
                    Text(content.value)
                        .font(Font(NotchStripGeometry.sideFont))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .frame(maxWidth: geometry.sideWidth, alignment: .trailing)
                        .focusReveal(isShown: isRevealed, hiddenScale: 0.6, delay: 0.02)
                }
                .frame(height: geometry.notchHeight)
                footer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, NotchStripGeometry.footerBottomInset)
                    .focusReveal(isShown: isRevealed, hiddenScale: 0.6, delay: 0.02)
            }
            .padding(.horizontal, NotchStripGeometry.sidePadding)
            .frame(width: geometry.size.width, height: geometry.size.height)
            // One blur for all items: it only lives as long as the notice, but held volume keys redraw it often.
            .blur(radius: isRevealed ? 0 : 6)
            .clipShape(shape)
        }
        .frame(width: geometry.windowFrame.width, height: geometry.windowFrame.height, alignment: .top)
    }

    @ViewBuilder
    private var footer: some View {
        switch content.footer {
        case .level(let level):
            Capsule()
                .fill(Color.white.opacity(0.18))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: geometry.footerWidth * CGFloat(level))
                }
                .frame(height: NotchStripGeometry.volumeBarHeight)
                .animation(.easeOut(duration: 0.12), value: level)
        case .title(let title):
            Text(title)
                .font(Font(NotchStripGeometry.footerFont))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// `base` drawn at `size`, centered at the top of whatever rect it is given; the size animates.
private struct TopCenteredShape: Shape {
    let base: NotchPanelShape
    var size: CGSize

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size.width, size.height) }
        set { size = CGSize(width: newValue.first, height: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        base.path(in: CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: size.height))
    }
}

/// The notch as a stem, flaring through concave fillets into a rounded body below it.
/// `progress` grows the body out of the notch; at `0` only the stem (hidden by the notch) remains.
private struct NotchNoticeShape: Shape {
    let geometry: NotchNoticeGeometry
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bodyHeight = NotchNoticeGeometry.bodyHeight * progress
        let top = geometry.stemHeight
        let bottom = top + bodyHeight
        let bodyLeft = rect.midX - geometry.bodyWidth / 2
        let bodyRight = rect.midX + geometry.bodyWidth / 2
        let radius = min(NotchNoticeGeometry.cornerRadius, bodyHeight / 2)

        guard geometry.stemWidth > 0 else {
            let bodyTop = geometry.growsUpward ? rect.maxY - bodyHeight : top
            let body = CGRect(x: bodyLeft, y: bodyTop, width: geometry.bodyWidth, height: bodyHeight)
            return Path(roundedRect: body, cornerRadius: radius)
        }

        let stemLeft = rect.midX - geometry.stemWidth / 2
        let stemRight = rect.midX + geometry.stemWidth / 2
        let fillet = min(NotchNoticeGeometry.fillet, bodyHeight / 2)

        var path = Path()
        path.move(to: CGPoint(x: stemLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: stemLeft, y: top - fillet))
        path.addQuadCurve(to: CGPoint(x: stemLeft - fillet, y: top), control: CGPoint(x: stemLeft, y: top))
        path.addLine(to: CGPoint(x: bodyLeft + radius, y: top))
        path.addQuadCurve(to: CGPoint(x: bodyLeft, y: top + radius), control: CGPoint(x: bodyLeft, y: top))
        path.addLine(to: CGPoint(x: bodyLeft, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: bodyLeft + radius, y: bottom), control: CGPoint(x: bodyLeft, y: bottom))
        path.addLine(to: CGPoint(x: bodyRight - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: bodyRight, y: bottom - radius), control: CGPoint(x: bodyRight, y: bottom))
        path.addLine(to: CGPoint(x: bodyRight, y: top + radius))
        path.addQuadCurve(to: CGPoint(x: bodyRight - radius, y: top), control: CGPoint(x: bodyRight, y: top))
        path.addLine(to: CGPoint(x: stemRight + fillet, y: top))
        path.addQuadCurve(to: CGPoint(x: stemRight, y: top - fillet), control: CGPoint(x: stemRight, y: top))
        path.addLine(to: CGPoint(x: stemRight, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
