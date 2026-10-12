import AppKit
import Combine
import SwiftUI

/// Briefly shows `ghbdtn → привет` growing down out of the notch after an automatic layout switch.
/// A separate click-through window, so it never takes part in the hover panel's lifecycle.
final class KeyboardSwitchNoticeController {
    private static let visibleDuration: TimeInterval = 1.8
    private static let hideAnimationDuration: TimeInterval = 0.22

    private let model = KeyboardSwitchNoticeModel()
    private var window: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var orderOutWorkItem: DispatchWorkItem?

    func show(original: String, replacement: String) {
        guard let screen = NSScreen.main else { return }
        let geometry = KeyboardSwitchNoticeGeometry(screen: screen, original: original, replacement: replacement)
        let window = window ?? makeWindow()
        self.window = window

        orderOutWorkItem?.cancel()
        model.original = original
        model.replacement = replacement
        model.geometry = geometry
        window.setFrame(geometry.windowFrame(on: screen), display: true)
        window.orderFrontRegardless()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            model.isRevealed = true
        }

        hideWorkItem?.cancel()
        let hide = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: hide)
    }

    func dismiss() {
        hideWorkItem?.cancel()
        guard model.isRevealed else { return }
        withAnimation(.easeIn(duration: Self.hideAnimationDuration)) {
            model.isRevealed = false
        }
        let orderOut = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil) }
        orderOutWorkItem = orderOut
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideAnimationDuration, execute: orderOut)
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
        panel.contentView = NSHostingView(rootView: KeyboardSwitchNoticeView(model: model))
        return panel
    }
}

final class KeyboardSwitchNoticeModel: ObservableObject {
    @Published var original = ""
    @Published var replacement = ""
    @Published var geometry = KeyboardSwitchNoticeGeometry()
    @Published var isRevealed = false
}

struct KeyboardSwitchNoticeGeometry {
    static let bodyHeight: CGFloat = 30
    static let fillet: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    static let contentSpacing: CGFloat = 8
    static let arrowWidth: CGFloat = 10
    static let maximumBodyWidth: CGFloat = 300
    /// Without a notch the notice floats this far below the menu bar instead of growing out of it.
    static let menuBarGap: CGFloat = 6
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// The stem sits behind the physical notch; zero on displays without one.
    var stemWidth: CGFloat = 0
    var stemHeight: CGFloat = 0
    var bodyWidth: CGFloat = 0

    var size: CGSize {
        CGSize(width: max(bodyWidth, stemWidth + Self.fillet * 2), height: stemHeight + Self.bodyHeight)
    }

    init() {}

    init(screen: NSScreen, original: String, replacement: String) {
        stemWidth = PanelLayout.notchWidth(on: screen)
        stemHeight = stemWidth > 0
            ? screen.auxiliaryTopLeftArea?.height ?? NSStatusBar.system.thickness
            : NSStatusBar.system.thickness + Self.menuBarGap

        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font]
        let textWidth = (original as NSString).size(withAttributes: attributes).width
            + (replacement as NSString).size(withAttributes: attributes).width
        let contentWidth = textWidth + Self.arrowWidth + Self.contentSpacing * 2 + Self.horizontalPadding * 2
        let minimumWidth = stemWidth > 0 ? stemWidth + (Self.fillet + Self.cornerRadius) * 2 : 0
        bodyWidth = min(max(contentWidth.rounded(.up), minimumWidth), max(Self.maximumBodyWidth, minimumWidth))
    }

    func windowFrame(on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

private struct KeyboardSwitchNoticeView: View {
    @ObservedObject var model: KeyboardSwitchNoticeModel
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    var body: some View {
        let geometry = model.geometry
        ZStack(alignment: .top) {
            KeyboardSwitchNoticeShape(geometry: geometry, progress: model.isRevealed ? 1 : 0)
                .fill(Color.black)

            HStack(spacing: KeyboardSwitchNoticeGeometry.contentSpacing) {
                Text(model.original)
                    .foregroundStyle(Color.white.opacity(0.45))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: accentColorHex))
                    .frame(width: KeyboardSwitchNoticeGeometry.arrowWidth)
                Text(model.replacement)
                    .foregroundStyle(Color.white)
            }
            .font(Font(KeyboardSwitchNoticeGeometry.font))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, KeyboardSwitchNoticeGeometry.horizontalPadding)
            .frame(width: geometry.bodyWidth, height: KeyboardSwitchNoticeGeometry.bodyHeight)
            .offset(y: geometry.stemHeight)
            .opacity(model.isRevealed ? 1 : 0)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
    }
}

/// The notch as a stem, flaring through concave fillets into a rounded body below it.
/// `progress` grows the body out of the notch; at `0` only the stem (hidden by the notch) remains.
private struct KeyboardSwitchNoticeShape: Shape {
    let geometry: KeyboardSwitchNoticeGeometry
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bodyHeight = KeyboardSwitchNoticeGeometry.bodyHeight * progress
        let top = geometry.stemHeight
        let bottom = top + bodyHeight
        let bodyLeft = rect.midX - geometry.bodyWidth / 2
        let bodyRight = rect.midX + geometry.bodyWidth / 2
        let radius = min(KeyboardSwitchNoticeGeometry.cornerRadius, bodyHeight / 2)

        guard geometry.stemWidth > 0 else {
            let body = CGRect(x: bodyLeft, y: top, width: geometry.bodyWidth, height: bodyHeight)
            return Path(roundedRect: body, cornerRadius: radius)
        }

        let stemLeft = rect.midX - geometry.stemWidth / 2
        let stemRight = rect.midX + geometry.stemWidth / 2
        let fillet = min(KeyboardSwitchNoticeGeometry.fillet, bodyHeight / 2)

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
