import AppKit
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var label: String

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onRecorded = { newKeyCode, newModifiers, newLabel in
            keyCode = newKeyCode
            modifiers = newModifiers
            label = newLabel
        }
        button.updateLabel(label)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onRecorded = { newKeyCode, newModifiers, newLabel in
            keyCode = newKeyCode
            modifiers = newModifiers
            label = newLabel
        }
        if !button.isRecording {
            button.updateLabel(label)
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var onRecorded: ((Int, Int, String) -> Void)?
    private(set) var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            updateLabel("Not set")
            onRecorded?(-1, 0, "Not set")
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shortcutLabel = Self.label(for: event, flags: flags)
        isRecording = false
        updateLabel(shortcutLabel)
        onRecorded?(Int(event.keyCode), Int(flags.rawValue), shortcutLabel)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.function) else { return }
        isRecording = false
        updateLabel("fn")
        onRecorded?(Int(event.keyCode), Int(NSEvent.ModifierFlags.function.rawValue), "fn")
        window?.makeFirstResponder(nil)
    }

    func updateLabel(_ label: String) {
        title = label
    }

    private static func label(for event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        if flags.contains(.function) { result += "fn " }

        let key: String
        switch event.keyCode {
        case 36: key = "↩"
        case 48: key = "⇥"
        case 49: key = "Space"
        case 51: key = "⌫"
        case 53: key = "Esc"
        case 123: key = "←"
        case 124: key = "→"
        case 125: key = "↓"
        case 126: key = "↑"
        default: key = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        return result + key
    }
}
