import AppKit

/// Briefly shows `ghbdtn → привет` next to the text caret after an automatic layout switch, or growing down
/// out of the notch when the app does not expose its caret through Accessibility.
final class KeyboardSwitchNoticeController {
    private let center: NotchNoticeCenter
    /// Bumped by every show and dismiss so a caret lookup that finishes late cannot reopen a dismissed notice.
    private var generation = 0

    init(center: NotchNoticeCenter) {
        self.center = center
    }

    func show(original: String, replacement: String) {
        generation += 1
        let request = generation
        guard !center.isSuppressed() else { return }
        // Accessibility blocks on the focused app, which is busy handling the synthetic keystrokes right now.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let caret = FocusedTextElement.caret()
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                let notice = NotchNotice.layoutSwitch(original: original, replacement: replacement)
                let contentWidth = notice.contentWidth
                let geometry = NotchNoticeGeometry(caret: caret, contentWidth: contentWidth)
                    ?? NSScreen.main.map { NotchNoticeGeometry(screen: $0, contentWidth: contentWidth) }
                guard let geometry else { return }
                self.center.present(notice, geometry: geometry)
            }
        }
    }

    func dismiss() {
        generation += 1
        center.dismiss(where: \.isLayoutSwitch)
    }
}
