import AppKit
import SwiftUI

final class TooltipManager {
    static let shared = TooltipManager()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TooltipContent>?
    private var currentText: String?
    private var suppressedUntil: Date?
    private var isPresentationEnabled = true

    private init() {}

    var canShow: Bool {
        guard isPresentationEnabled else { return false }
        guard let suppressedUntil else { return true }
        return Date() >= suppressedUntil
    }

    func setPresentationEnabled(_ isEnabled: Bool) {
        isPresentationEnabled = isEnabled
        if !isEnabled {
            hide()
        }
    }

    func suppressShowing(for interval: TimeInterval) {
        hide()
        suppressedUntil = Date().addingTimeInterval(interval)
    }

    func show(text: String, nearCursorOffset offset: CGSize = CGSize(width: 14, height: 10)) {
        show(text: text, near: NSEvent.mouseLocation, offset: offset)
    }

    func show(text: String, near cursorPoint: NSPoint, offset: CGSize = CGSize(width: 14, height: 10)) {
        guard canShow else { return }

        let fittedSize = tooltipSize(for: text)
        let hostingView = tooltipHostingView(for: text, width: fittedSize.width)
        hostingView.frame = NSRect(origin: .zero, size: fittedSize)
        hostingView.layoutSubtreeIfNeeded()

        let screenFrame = NSScreen.screens.first { NSMouseInRect(cursorPoint, $0.frame, false) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(origin: cursorPoint, size: fittedSize)
        let preferredX = cursorPoint.x + offset.width
        let preferredY = cursorPoint.y - fittedSize.height - offset.height
        let x = min(max(preferredX, screenFrame.minX + 4), screenFrame.maxX - fittedSize.width - 4)
        let y = min(max(preferredY, screenFrame.minY + 4), screenFrame.maxY - fittedSize.height - 4)
        let frame = NSRect(x: x, y: y, width: fittedSize.width, height: fittedSize.height)

        if let panel {
            panel.setFrame(frame, display: true)
            panel.orderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        currentText = nil
    }

    private func tooltipHostingView(for text: String, width: CGFloat) -> NSHostingView<TooltipContent> {
        if let hostingView {
            if currentText != text {
                hostingView.rootView = TooltipContent(text: text, width: width)
                currentText = text
            }
            return hostingView
        }

        let hostingView = NSHostingView(rootView: TooltipContent(text: text, width: width))
        self.hostingView = hostingView
        currentText = text
        return hostingView
    }

    private func tooltipSize(for text: String) -> NSSize {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TooltipContent.font,
            .paragraphStyle: paragraphStyle
        ]
        let longestLineWidth = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { (String($0) as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        let width = min(
            max(ceil(longestLineWidth) + TooltipContent.horizontalPadding * 2, TooltipContent.minimumWidth),
            TooltipContent.maximumWidth
        )
        let textWidth = width - TooltipContent.horizontalPadding * 2
        let textRect = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let height = max(
            ceil(textRect.height) + TooltipContent.verticalPadding * 2,
            TooltipContent.minimumHeight
        )
        return NSSize(width: width, height: height)
    }
}

private struct TooltipContent: View {
    static let maximumWidth: CGFloat = 260
    static let minimumWidth: CGFloat = 44
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 7
    static let minimumHeight: CGFloat = 34
    static let font = NSFont.systemFont(ofSize: 11, weight: .regular)

    let text: String
    let width: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.black.opacity(0.88))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .frame(width: width - Self.horizontalPadding * 2, alignment: .leading)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

/// Shows a `TooltipManager` tooltip while the pointer is over the view, without taking clicks.
struct PanelTooltipTrackingView: NSViewRepresentable {
    let text: String
    var isPanelContentVisible = true

    func makeNSView(context: Context) -> PanelTooltipTrackingNSView {
        let view = PanelTooltipTrackingNSView(frame: .zero)
        view.text = text
        view.isPanelContentVisible = isPanelContentVisible
        return view
    }

    func updateNSView(_ nsView: PanelTooltipTrackingNSView, context: Context) {
        nsView.text = text
        nsView.isPanelContentVisible = isPanelContentVisible
    }
}

final class PanelTooltipTrackingNSView: NSView {
    var text = ""
    var isPanelContentVisible = true {
        didSet {
            guard isPanelContentVisible != oldValue, !isPanelContentVisible else { return }
            TooltipManager.shared.hide()
        }
    }
    private var trackingArea: NSTrackingArea?
    private var canShowDuringCurrentHover = true

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        guard isPanelContentVisible else { return }

        guard TooltipManager.shared.canShow else {
            canShowDuringCurrentHover = false
            TooltipManager.shared.hide()
            super.mouseEntered(with: event)
            return
        }

        canShowDuringCurrentHover = true
        showTooltip(for: event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        canShowDuringCurrentHover = true
        TooltipManager.shared.hide()
        super.mouseExited(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            TooltipManager.shared.hide()
        }
    }

    override func viewDidHide() {
        TooltipManager.shared.hide()
        super.viewDidHide()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            TooltipManager.shared.hide()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func showTooltip(for event: NSEvent) {
        guard canShowDuringCurrentHover,
              isPanelContentVisible,
              let window,
              window.isVisible,
              !isHiddenOrHasHiddenAncestor
        else { return }
        let cursorRect = NSRect(origin: event.locationInWindow, size: .zero)
        let cursorPoint = window.convertToScreen(cursorRect).origin
        TooltipManager.shared.show(text: text, near: cursorPoint)
    }
}
