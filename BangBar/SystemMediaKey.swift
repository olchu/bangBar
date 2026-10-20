import AppKit
import IOKit.hidsystem

/// The hardware media keys, posted the way the keyboard sends them, so macOS hands them to the app it treats
/// as now playing. Posting events needs Accessibility; without it the keys are dropped.
enum SystemMediaKey {
    case playPause
    case next
    case previous

    private var keyType: Int32 {
        switch self {
        case .playPause: NX_KEYTYPE_PLAY
        case .next: NX_KEYTYPE_NEXT
        case .previous: NX_KEYTYPE_PREVIOUS
        }
    }

    /// False when the keys could not be posted, so the caller shows no state the app never reached.
    @discardableResult
    func post() -> Bool {
        guard AccessibilityAccess.isTrusted else { return false }
        for state in [NX_KEYDOWN, NX_KEYUP] {
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: Int(keyType) << 16 | Int(state) << 8,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }
}
