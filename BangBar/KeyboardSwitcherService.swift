import AppKit
import ApplicationServices
import Carbon
import OSLog

final class KeyboardSwitcherService {
    private static let shortcutModifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn
    ]

    private let logger = Logger(subsystem: "BangBar", category: "KeyboardSwitcher")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var buffer = KeyboardWordBuffer()
    private var shiftTaps = DoubleTapDetector()
    private var currentLayout: KeyboardLayout?
    private var swallowedKeyUpCode: UInt16?
    private var isConvertingSelection = false

    func start() {
        let defaults = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observers = [
            (defaults, defaults.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateState() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetTypingState() }
            }),
            (distributed, distributed.addObserver(
                forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.currentLayout = KeyboardLayouts.current() }
            })
        ]
        currentLayout = KeyboardLayouts.current()
        updateState()
    }

    func stop() {
        observers.forEach { center, token in center.removeObserver(token) }
        observers.removeAll()
        removeTap()
        stopPermissionPolling()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: BangBarSettings.Key.keyboardSwitcherEnabled)
    }

    private func updateState() {
        guard isEnabled else {
            removeTap()
            stopPermissionPolling()
            return
        }
        guard eventTap == nil else { return }
        if AXIsProcessTrusted() {
            stopPermissionPolling()
            installTap()
        } else {
            startPermissionPolling()
        }
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                self?.updateState()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - Event Tap

    private func installTap() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<KeyboardSwitcherService>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { service.handle(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Failed to create keyboard event tap")
            startPermissionPolling()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func removeTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        resetTypingState()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return passThrough
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            resetTypingState()
            return passThrough
        default:
            break
        }

        guard !SyntheticKeyboard.isSynthetic(event) else {
            return passThrough
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
            return passThrough
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == swallowedKeyUpCode {
                swallowedKeyUpCode = nil
                return nil
            }
            return passThrough
        default:
            return passThrough
        }
    }

    // MARK: - Triggers

    private var trigger: KeyboardSwitcherTrigger {
        KeyboardSwitcherTrigger(
            rawValue: UserDefaults.standard.string(forKey: BangBarSettings.Key.keyboardSwitcherTrigger) ?? ""
        ) ?? .doubleShift
    }

    private var customShortcut: (keyCode: Int, modifiers: CGEventFlags)? {
        let defaults = UserDefaults.standard
        let keyCode = defaults.integer(forKey: BangBarSettings.Key.keyboardSwitcherShortcutKeyCode)
        guard keyCode >= 0 else { return nil }
        let modifiers = UInt64(defaults.integer(forKey: BangBarSettings.Key.keyboardSwitcherShortcutModifiers))
        return (keyCode, CGEventFlags(rawValue: modifiers).intersection(Self.shortcutModifierMask))
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if trigger == .custom, let shortcut = customShortcut,
           shortcut.modifiers == .maskSecondaryFn, keyCode == shortcut.keyCode,
           flags.contains(.maskSecondaryFn) {
            scheduleConversion()
            return
        }

        guard trigger == .doubleShift, keyCode == kVK_Shift || keyCode == kVK_RightShift else {
            shiftTaps.interrupt()
            return
        }
        guard flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty else {
            shiftTaps.interrupt()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if flags.contains(.maskShift) {
            shiftTaps.press(at: now)
        } else if shiftTaps.release(at: now) {
            scheduleConversion()
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        shiftTaps.interrupt()
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if trigger == .custom, let shortcut = customShortcut,
           Int(keyCode) == shortcut.keyCode,
           flags.intersection(Self.shortcutModifierMask) == shortcut.modifiers {
            swallowedKeyUpCode = keyCode
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                scheduleConversion()
            }
            return nil
        }

        record(keyCode: keyCode, flags: flags)
        return Unmanaged.passUnretained(event)
    }

    private func record(keyCode: UInt16, flags: CGEventFlags) {
        if !flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty {
            buffer.reset()
            return
        }
        switch Int(keyCode) {
        case kVK_Space:
            buffer.appendSpace()
            return
        case kVK_Delete:
            buffer.deleteBackward()
            return
        default:
            break
        }
        let keystroke = TypedKeystroke(
            keyCode: keyCode,
            shift: flags.contains(.maskShift),
            capsLock: flags.contains(.maskAlphaShift)
        )
        // Printability comes from the layout, not the event: dead keys report no characters.
        guard let currentLayout, KeyboardLayouts.isPrintable(keystroke, in: currentLayout) else {
            buffer.reset()
            return
        }
        buffer.appendCharacter(keystroke, layoutID: currentLayout.id)
    }

    private func resetTypingState() {
        buffer.reset()
        shiftTaps.interrupt()
        swallowedKeyUpCode = nil
    }

    // MARK: - Conversion

    // Posting from inside the tap callback would interleave with the event being handled.
    private func scheduleConversion() {
        DispatchQueue.main.async { [weak self] in
            self?.convert()
        }
    }

    // Selecting text (mouse, arrows, ⌘A) always resets the word buffer, so a non-empty
    // buffer means the user was just typing and there is no selection to convert.
    private func convert() {
        guard !isConvertingSelection else { return }
        if buffer.isEmpty {
            convertSelection()
        } else {
            convertLastWord()
        }
    }

    private func convertSelection() {
        isConvertingSelection = true
        Task {
            if let target = await SelectedTextConverter.convertSelection() {
                currentLayout = target
            }
            isConvertingSelection = false
        }
    }

    private func convertLastWord() {
        guard let wordLayoutID = buffer.layoutID else { return }
        let layouts = KeyboardLayouts.enabled()
        guard layouts.count > 1,
              let fromIndex = layouts.firstIndex(where: { $0.id == wordLayoutID }) else { return }
        let source = layouts[fromIndex]
        let target = layouts[(fromIndex + 1) % layouts.count]

        let spaces = String(repeating: " ", count: buffer.trailingSpaces)
        let onScreen = KeyboardLayouts.translate(buffer.keystrokes, with: source, composingDeadKeys: true)
        let replacement = KeyboardLayouts.translate(buffer.keystrokes, with: target)
        guard !replacement.isEmpty else { return }

        SyntheticKeyboard.deleteBackward(count: onScreen.count + spaces.count)
        SyntheticKeyboard.type(replacement + spaces)

        KeyboardLayouts.select(target)
        currentLayout = target
        buffer.markConverted(to: target.id)
    }
}
