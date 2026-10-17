import AppKit
import SwiftUI

@MainActor
final class ClipboardImagePreviewWindowController: NSWindowController {
    static let shared = ClipboardImagePreviewWindowController()

    private init() {
        let window = ClipboardImagePreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Image"
        window.minSize = NSSize(width: 240, height: 180)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .black
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ image: NSImage) {
        guard let window else { return }
        window.contentView = NSHostingView(rootView: ClipboardImagePreviewView(image: image))

        // `NSWindow.center()` places windows in the upper third; the preview should sit exactly in the middle.
        let screen = NSScreen.containing(NSEvent.mouseLocation)
        if let visibleFrame = screen?.visibleFrame {
            let size = fittedSize(for: image.size, in: visibleFrame.size)
            let origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func fittedSize(for imageSize: NSSize, in bounds: NSSize) -> NSSize {
        let maxWidth = bounds.width * 0.8
        let maxHeight = bounds.height * 0.8
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: maxWidth, height: maxHeight)
        }
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1)
        return NSSize(
            width: max(imageSize.width * scale, 240),
            height: max(imageSize.height * scale, 180)
        )
    }
}

private final class ClipboardImagePreviewWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private struct ClipboardImagePreviewView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea()
    }
}
