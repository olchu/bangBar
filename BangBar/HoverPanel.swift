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
            x: (screen.frame.width - 560) / 2,
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

        // Panel sits flush at the top of the screen, covering the menu bar area
        let targetFrame = NSRect(
            x: (screen.frame.width - panelWidth) / 2,
            y: screen.frame.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )

        if !isVisible {
            let startFrame = NSRect(
                x: targetFrame.minX,
                y: screen.frame.maxY,
                width: panelWidth,
                height: panelHeight
            )
            setFrame(startFrame, display: false)
            orderFront(nil)
            alphaValue = 1.0
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            animator().setFrame(targetFrame, display: true)
        }
    }

    func slideOut() {
        isHiding = true
        guard let screen = NSScreen.main else { return }

        let hiddenFrame = NSRect(
            x: self.frame.minX,
            y: screen.frame.maxY,
            width: panelWidth,
            height: panelHeight
        )

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
