import Carbon
import CoreGraphics

enum SyntheticKeyboard {
    private static let marker: Int64 = 0x4B42_5357
    private static let source = CGEventSource(stateID: .privateState)

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    static func deleteBackward(count: Int) {
        for _ in 0..<count {
            press(CGKeyCode(kVK_Delete))
        }
    }

    static func type(_ text: String) {
        for character in text {
            press(0, text: String(character))
        }
    }

    static func selectBackward(count: Int) {
        for _ in 0..<count {
            press(CGKeyCode(kVK_LeftArrow), flags: .maskShift)
        }
    }

    // Flags are always set explicitly so a modifier the user still holds never alters the key.
    static func press(_ keyCode: CGKeyCode, flags: CGEventFlags = [], text: String? = nil) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.post(tap: .cgSessionEventTap)
        }
    }
}
