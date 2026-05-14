import AppKit
import SwiftUI

class HoverPanel: NSPanel {
    var isHiding = false
    private var panelHeight: CGFloat = 150
    private var panelWidth: CGFloat = 560

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
            y: screen.frame.maxY,
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
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let contentView = NSHostingView(rootView: PanelContentView())
        contentView.wantsLayer = true
        self.contentView = contentView
    }

    // MARK: - Animation

    func slideIn() {
        isHiding = false

        guard let screen = NSScreen.main else { return }

        let visibleFrame = centeredFrame(on: screen, y: screen.frame.maxY - panelHeight)

        if !isVisible {
            let hiddenFrame = centeredFrame(on: screen, y: screen.frame.maxY)
            setFrame(hiddenFrame, display: false)
            orderFront(nil)
            alphaValue = 1.0
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            animator().setFrame(visibleFrame, display: true)
        }
    }

    private func centeredFrame(on screen: NSScreen, y: CGFloat) -> NSRect {
        NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: y,
            width: panelWidth,
            height: panelHeight
        )
    }

    func slideOut() {
        isHiding = true

        guard let screen = NSScreen.main else { return }

        let hiddenFrame = centeredFrame(on: screen, y: screen.frame.maxY)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(hiddenFrame, display: true)
        }, completionHandler: { [weak self] in
            if self?.isHiding == true {
                self?.orderOut(nil)
                self?.isHiding = false
            }
        })
    }
}
