import AppKit
import SwiftUI

final class TooltipManager {
    static let shared = TooltipManager()
    private var panel: NSPanel?

    private init() {}

    func show(text: String) {
        hide()

        let hostingView = NSHostingView(rootView: TooltipContent(text: text))
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 200)
        hostingView.layoutSubtreeIfNeeded()
        let fittedSize = hostingView.fittingSize

        let mouse = mouseLocationInScreenCoordinates()
        // Position tooltip to the right and slightly below the cursor
        // Clamp so it stays within screen bounds
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let sx = min(mouse.x + 14, screen.frame.maxX - fittedSize.width - 4)
        let sy = max(mouse.y - fittedSize.height - 8, screen.frame.minY + 4)
        let frame = NSRect(x: sx, y: sy, width: fittedSize.width, height: fittedSize.height)

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
        panel.contentView = hostingView
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // CGEvent gives the most reliable global mouse position.
    // Its Y is from top of primary screen; convert to NS (bottom-origin) coordinates.
    private func mouseLocationInScreenCoordinates() -> NSPoint {
        if let cgEvent = CGEvent(source: nil) {
            let loc = cgEvent.location
            let primaryHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main!.frame.height
            return NSPoint(x: loc.x, y: primaryHeight - loc.y)
        }
        return NSEvent.mouseLocation
    }
}

private struct TooltipContent: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.white.opacity(0.88))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 240, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0.13, green: 0.13, blue: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
    }
}
