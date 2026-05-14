import AppKit
import SwiftUI

class HoverPanel: NSPanel {
    var isHiding = false
    private var panelHeight: CGFloat = 150
    private var panelWidth: CGFloat = 560
    private let state = PanelState()
    private var hideWorkItem: DispatchWorkItem?
    private let hideDelay: TimeInterval = 0.45
    private var openedAt: Date = .distantPast

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setupPanel()
    }

    convenience init() {
        let screen = NSScreen.main!
        let initialRect = NSRect(
            x: screen.frame.midX - 560 / 2,
            y: screen.frame.maxY - 150,
            width: 560,
            height: 150
        )
        self.init(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func setupPanel() {
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let contentView = NSHostingView(rootView: PanelContentView(state: state))
        contentView.wantsLayer = true
        self.contentView = contentView
    }

    // MARK: - Animation

    func slideIn() {
        isHiding = false
        openedAt = Date()
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let screen = NSScreen.main else { return }
        setFrame(expandedFrame(on: screen), display: true)

        if !isVisible {
            state.isExpanded = false
            state.contentVisible = false
            orderFront(nil)
        }

        DispatchQueue.main.async { [weak self] in
            self?.state.isExpanded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                self?.state.contentVisible = true
            }
        }
    }

    func slideOut() {
        guard Date().timeIntervalSince(openedAt) > 0.5 else { return }
        isHiding = true

        state.isExpanded = false
        state.contentVisible = false

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isHiding {
                self.orderOut(nil)
                self.isHiding = false
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: screen.frame.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )
    }
}
