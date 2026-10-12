import Carbon
import CoreGraphics

enum SyntheticKeyboard {
    private static let marker: Int64 = 0x4B42_5357
    private static let source = CGEventSource(stateID: .privateState)

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    static func deleteBackward(count: Int, via proxy: CGEventTapProxy? = nil) {
        for _ in 0..<count {
            press(CGKeyCode(kVK_Delete), via: proxy)
        }
    }

    static func type(_ text: String, via proxy: CGEventTapProxy? = nil) {
        for character in text {
            press(0, text: String(character), via: proxy)
        }
    }

    static func selectBackward(count: Int) {
        for _ in 0..<count {
            press(CGKeyCode(kVK_LeftArrow), flags: .maskShift)
        }
    }

    // Flags are always set explicitly so a modifier the user still holds never alters the key.
    // With a tap proxy (from inside the tap callback) events go downstream of the tap, ahead of any
    // keys the user has already pressed; without one they enter at the session level.
    static func press(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        text: String? = nil,
        via proxy: CGEventTapProxy? = nil
    ) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            post(event, via: proxy)
        }
    }

    static func post(_ event: CGEvent, via proxy: CGEventTapProxy?) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }
}
