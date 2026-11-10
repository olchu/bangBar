import AppKit

/// Owns the panel's shell session for the life of the app, so hiding the panel never ends it.
final class TerminalSessionService {
    var onSessionEnded: (() -> Void)?
    private var surface: TerminalSurfaceView?
    private var layoutBeforeFocus: KeyboardLayout?

    var hasKeyboardFocus: Bool {
        surface?.hasKeyboardFocus == true
    }

    func makeSurface() -> TerminalSurfaceView {
        if let surface { return surface }
        let surface = TerminalSurfaceView()
        surface.onProcessTermination = { [weak self, weak surface] in
            guard let self, let surface, self.surface === surface else { return }
            self.discard(surface)
            self.onSessionEnded?()
        }
        self.surface = surface
        return surface
    }

    func focus(accentColor: NSColor) {
        guard let surface else { return }
        surface.setAccentColor(accentColor)
        surface.setVisible(true)
        surface.focusTerminal()
        guard layoutBeforeFocus == nil, let current = KeyboardLayouts.current() else { return }
        layoutBeforeFocus = current
        if current.language != "en", let english = KeyboardLayouts.enabled().first(where: { $0.language == "en" }) {
            KeyboardLayouts.select(english)
        }
    }

    func didHide() {
        surface?.setVisible(false)
        if let layoutBeforeFocus {
            KeyboardLayouts.select(layoutBeforeFocus)
            self.layoutBeforeFocus = nil
        }
    }

    func terminate() {
        didHide()
        if let surface { discard(surface) }
    }

    private func discard(_ surface: TerminalSurfaceView) {
        surface.terminateSession()
        surface.removeFromSuperview()
        self.surface = nil
    }
}
