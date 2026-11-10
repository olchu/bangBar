import AppKit
import Carbon

/// A system-wide shortcut registered with `RegisterEventHotKey`: needs no Accessibility access, and the
/// focused app never receives the keystroke. Adapted from DropTerm.
final class GlobalHotKey {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: () -> Void
    private static let identifier = EventHotKeyID(signature: 0x4242_4152, id: 1) // BBAR

    /// Returns nil for shortcuts without ⌘, ⌃ or ⌥, which would swallow ordinary typing.
    init?(keyCode: Int, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        guard keyCode >= 0, !modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressedID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard pressedID.signature == GlobalHotKey.identifier.signature, pressedID.id == GlobalHotKey.identifier.id else {
                    return OSStatus(eventNotHandledErr)
                }
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else { return nil }

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(modifiers),
            Self.identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr else {
            invalidate()
            return nil
        }
    }

    /// The Carbon handler holds an unretained pointer to this object.
    isolated deinit {
        invalidate()
    }

    func invalidate() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
