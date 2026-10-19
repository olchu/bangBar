import AppKit
import Combine
import SwiftUI

enum NotchNotice {
    case layoutSwitch(original: String, replacement: String)
    case activity(LiveActivity)

    var visibleDuration: TimeInterval {
        switch self {
        case .layoutSwitch: 1.8
        case .activity: 2.4
        }
    }

    var contentWidth: CGFloat {
        switch self {
        case .layoutSwitch(let original, let replacement):
            NotchNoticeGeometry.contentWidth(texts: [original, replacement], glyphWidth: NotchNoticeGeometry.arrowWidth)
        case .activity(let activity):
            NotchNoticeGeometry.contentWidth(texts: [activity.title, activity.detail], glyphWidth: NotchNoticeGeometry.symbolWidth)
        }
    }

    var isLayoutSwitch: Bool {
        if case .layoutSwitch = self { return true }
        return false
    }
}

/// The one channel for notices that grow out of the notch: a new notice replaces the visible one, and none is
/// shown while `isSuppressed` (the expanded panel already shows the same information). A separate click-through
/// window, so a notice never takes part in the hover panel's lifecycle.
final class NotchNoticeCenter {
    private static let hideAnimationDuration: TimeInterval = 0.22

    var isSuppressed: () -> Bool = { false }
    private let state = NotchNoticeState()
    private var window: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var orderOutWorkItem: DispatchWorkItem?

    /// Without a `geometry` the notice grows out of the notch, on the screen that has one.
    func present(_ notice: NotchNotice, geometry: NotchNoticeGeometry? = nil) {
        guard !isSuppressed(),
              let geometry = geometry ?? Self.notchScreen.map({ NotchNoticeGeometry(screen: $0, contentWidth: notice.contentWidth) })
        else { return }
        let window = window ?? makeWindow()
        self.window = window

        orderOutWorkItem?.cancel()
        state.notice = notice
        state.geometry = geometry
        window.setFrame(geometry.windowFrame, display: true)
        window.orderFrontRegardless()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            state.isRevealed = true
        }

        hideWorkItem?.cancel()
        let hide = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + notice.visibleDuration, execute: hide)
    }

    func dismiss(where matches: (NotchNotice) -> Bool = { _ in true }) {
        guard state.isRevealed, let notice = state.notice, matches(notice) else { return }
        hideWorkItem?.cancel()
        withAnimation(.easeIn(duration: Self.hideAnimationDuration)) {
            state.isRevealed = false
        }
        let orderOut = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil) }
        orderOutWorkItem = orderOut
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideAnimationDuration, execute: orderOut)
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
    @Published var notice: NotchNotice?
    @Published var geometry = NotchNoticeGeometry()
    @Published var isRevealed = false
}

struct NotchNoticeGeometry {
    static let bodyHeight: CGFloat = 30
    static let fillet: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    static let contentSpacing: CGFloat = 8
    static let arrowWidth: CGFloat = 10
    static let symbolWidth: CGFloat = 16
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

    init() {}

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

    /// Body width for one line of `texts` plus one fixed-width glyph between or before them.
    static func contentWidth(texts: [String], glyphWidth: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = texts.reduce(0) { $0 + ($1 as NSString).size(withAttributes: attributes).width }
        return (textWidth + glyphWidth + contentSpacing * 2 + horizontalPadding * 2).rounded(.up)
    }
}

private struct NotchNoticeView: View {
    @ObservedObject var state: NotchNoticeState
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    var body: some View {
        let geometry = state.geometry
        let shape = NotchNoticeShape(geometry: geometry, progress: state.isRevealed ? 1 : 0)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            // Away from the notch the black body needs an edge to stand out against dark windows.
            if geometry.stemWidth == 0 {
                shape.stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .opacity(state.isRevealed ? 1 : 0)
            }

            HStack(spacing: NotchNoticeGeometry.contentSpacing) {
                content
            }
            .font(Font(NotchNoticeGeometry.font))
            .lineLimit(1)
            .padding(.horizontal, NotchNoticeGeometry.horizontalPadding)
            .frame(width: geometry.bodyWidth, height: NotchNoticeGeometry.bodyHeight)
            .offset(y: geometry.stemHeight)
            .opacity(state.isRevealed ? 1 : 0)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch state.notice {
        case .layoutSwitch(let original, let replacement):
            Text(original)
                .foregroundStyle(Color.white.opacity(0.45))
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: accentColorHex))
                .frame(width: NotchNoticeGeometry.arrowWidth)
            Text(replacement)
                .foregroundStyle(Color.white)
                .truncationMode(.middle)
        case .activity(let activity):
            Image(systemName: activity.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: accentColorHex))
                .frame(width: NotchNoticeGeometry.symbolWidth)
            Text(activity.title)
                .foregroundStyle(Color.white)
            Text(activity.detail)
                .foregroundStyle(Color.white.opacity(0.45))
                .fixedSize()
        case nil:
            EmptyView()
        }
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
