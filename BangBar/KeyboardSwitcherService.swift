import AppKit
import ApplicationServices
import Carbon

final class KeyboardSwitcherService: NSObject {
    private static let shortcutModifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn
    ]
    private static let commandModifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    private static let autoSwitchBoundaryKeys: Set<Int> = [kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter]

    private lazy var eventTap = EventTap(
        name: "keyboard",
        mask: EventTap.mask([.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown])
    ) { [weak self] type, event, proxy in
        self?.handle(type: type, event: event, proxy: proxy) ?? .pass
    }
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var buffer = KeyboardWordBuffer()
    private var shiftTaps = DoubleTapDetector()
    private var currentLayout: KeyboardLayout?
    private var swallowedKeyUpCode: UInt16?
    private var isConvertingSelection = false
    private let autoSwitcher = KeyboardAutoSwitcher()
    private var undoableAutoSwitch: AutoSwitchPlan?
    /// The word as first typed, kept across repeated manual conversions so cycling through layouts learns
    /// the final result relative to the original rather than to an intermediate layout.
    private var manualConversionOrigin: (keystrokes: [TypedKeystroke], layoutID: String)?
    var onAutoSwitch: ((_ original: String, _ replacement: String) -> Void)?
    var onAutoSwitchUndo: (() -> Void)?

    func start() {
        let defaults = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (defaults, defaults.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateState() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                MainActor.assumeIsolated {
                    self?.autoSwitcher.setFrontmostApp(bundleID)
                    self?.resetTypingState()
                }
            })
        ]
        // AppKit suspends distributed notifications while the app is inactive, which for a menu bar app is
        // nearly always; without immediate delivery the cached layout goes stale after a manual switch.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(enabledInputSourcesChanged),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        distributed.addObserver(
            self,
            selector: #selector(selectedInputSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        currentLayout = KeyboardLayouts.current()
        autoSwitcher.refreshLayouts()
        autoSwitcher.setFrontmostApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        updateState()
    }

    func stop() {
        observers.forEach { center, token in center.removeObserver(token) }
        observers.removeAll()
        DistributedNotificationCenter.default().removeObserver(self)
        eventTap.isEnabled = false
        resetTypingState()
    }

    @objc private func enabledInputSourcesChanged() {
        autoSwitcher.refreshLayouts()
    }

    @objc private func selectedInputSourceChanged() {
        currentLayout = KeyboardLayouts.current()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: BangBarSettings.Key.keyboardSwitcherEnabled)
    }

    private func updateState() {
        reloadTriggerSettings()
        autoSwitcher.reloadSettings()
        guard isEnabled else {
            eventTap.isEnabled = false
            resetTypingState()
            return
        }
        autoSwitcher.prepareLanguagesIfNeeded()
        eventTap.isEnabled = true
    }

    // MARK: - Event Tap

    private func handle(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> EventTapDecision {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            resetTypingState()
            return .pass
        default:
            break
        }

        guard !SyntheticKeyboard.isSynthetic(event) else {
            return .pass
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
            return .pass
        case .keyDown:
            return handleKeyDown(event, proxy: proxy)
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == swallowedKeyUpCode {
                swallowedKeyUpCode = nil
                return .swallow
            }
            return .pass
        default:
            return .pass
        }
    }

    // MARK: - Triggers

    // Cached by `reloadTriggerSettings()`: both are read for every key event the tap sees.
    private var trigger = KeyboardSwitcherTrigger.doubleShift
    private var customShortcut: (keyCode: Int, modifiers: CGEventFlags)?

    private func reloadTriggerSettings() {
        let defaults = UserDefaults.standard
        trigger = KeyboardSwitcherTrigger(
            rawValue: defaults.string(forKey: BangBarSettings.Key.keyboardSwitcherTrigger) ?? ""
        ) ?? .doubleShift
        let keyCode = defaults.integer(forKey: BangBarSettings.Key.keyboardSwitcherShortcutKeyCode)
        let modifiers = UInt64(defaults.integer(forKey: BangBarSettings.Key.keyboardSwitcherShortcutModifiers))
        customShortcut = keyCode >= 0
            ? (keyCode, CGEventFlags(rawValue: modifiers).intersection(Self.shortcutModifierMask))
            : nil
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
        guard flags.intersection(Self.commandModifierMask).isEmpty else {
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

    private func handleKeyDown(_ event: CGEvent, proxy: CGEventTapProxy) -> EventTapDecision {
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
            return .swallow
        }

        let undoable = undoableAutoSwitch
        undoableAutoSwitch = nil
        if flags.intersection(Self.commandModifierMask).isEmpty {
            if Int(keyCode) == kVK_Delete, let undoable, undoAutoSwitch(undoable, proxy: proxy) {
                return .swallow
            }
            if Self.autoSwitchBoundaryKeys.contains(Int(keyCode)), autoSwitch(before: event, proxy: proxy) {
                return .swallow
            }
        }

        record(keyCode: keyCode, flags: flags)
        return .pass
    }

    private func record(keyCode: UInt16, flags: CGEventFlags) {
        if !flags.intersection(Self.commandModifierMask).isEmpty {
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
        // The word's layout decides how it is converted, so re-read it as each word starts
        // instead of trusting notifications alone.
        if buffer.isEmpty || buffer.trailingSpaces > 0 {
            currentLayout = KeyboardLayouts.currentLayoutID().flatMap(autoSwitcher.layout(withID:))
                ?? KeyboardLayouts.current()
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
        undoableAutoSwitch = nil
        manualConversionOrigin = nil
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
            // Reverting an automatic switch by hand counts as an undo, not as something to learn.
            if let undoable = undoableAutoSwitch {
                autoSwitcher.rememberUndo(for: undoable)
                undoableAutoSwitch = nil
                convertLastWord(learns: false)
            } else {
                convertLastWord(learns: true)
            }
        }
    }

    private func convertSelection() {
        isConvertingSelection = true
        Task {
            if let target = await SelectedTextConverter.convertSelection(among: autoSwitcher.enabledLayouts) {
                currentLayout = target
            }
            isConvertingSelection = false
        }
    }

    private func convertLastWord(learns: Bool) {
        guard let wordLayoutID = buffer.layoutID else { return }
        let layouts = autoSwitcher.enabledLayouts
        guard layouts.count > 1,
              let fromIndex = layouts.firstIndex(where: { $0.id == wordLayoutID }) else { return }
        let source = layouts[fromIndex]
        let target = layouts[(fromIndex + 1) % layouts.count]

        let onScreen = KeyboardLayouts.render([buffer.current], with: source, composingDeadKeys: true)
        let replacement = KeyboardLayouts.render([buffer.current], with: target)
        guard replacement.count > buffer.trailingSpaces else { return }

        SyntheticKeyboard.deleteBackward(count: onScreen.count)
        SyntheticKeyboard.type(replacement)

        KeyboardLayouts.select(target)
        currentLayout = target

        if !learns {
            manualConversionOrigin = nil
        } else if manualConversionOrigin?.keystrokes != buffer.keystrokes {
            manualConversionOrigin = (buffer.keystrokes, wordLayoutID)
        }
        if let origin = manualConversionOrigin {
            autoSwitcher.learnManualConversion(of: origin.keystrokes, from: origin.layoutID, to: target.id)
        }
        buffer.markConverted(to: target.id)
    }

    // MARK: - Automatic Conversion

    // Runs inside the tap callback and posts through the proxy, so the corrected word and the boundary key
    // reach the app before any key the user pressed after it.
    private func autoSwitch(before boundary: CGEvent, proxy: CGEventTapProxy) -> Bool {
        guard buffer.trailingSpaces == 0, !buffer.isEmpty, let plan = autoSwitcher.plan(for: buffer) else { return false }

        let words = Array(buffer.previousWords.suffix(plan.previousWordCount) + [buffer.current])
        let onScreen = KeyboardLayouts.render(words, with: plan.source, composingDeadKeys: true)
        let replacement = KeyboardLayouts.render(words, with: plan.target)
        SyntheticKeyboard.deleteBackward(count: onScreen.count, via: proxy)
        SyntheticKeyboard.type(replacement, via: proxy)
        if let boundaryCopy = boundary.copy() {
            SyntheticKeyboard.post(boundaryCopy, via: proxy)
        }

        KeyboardLayouts.select(plan.target)
        currentLayout = plan.target
        buffer.markConverted(to: plan.target.id, includingPrevious: plan.previousWordCount)
        if Int(boundary.getIntegerValueField(.keyboardEventKeycode)) == kVK_Space {
            buffer.appendSpace()
            undoableAutoSwitch = plan
        } else {
            buffer.reset()
        }
        // Showing a window inside the tap callback would delay the user's next keystrokes.
        DispatchQueue.main.async { [weak self] in
            self?.onAutoSwitch?(KeyboardLayouts.render(words, with: plan.source), replacement)
        }
        return true
    }

    /// Backspace right after an automatic switch restores the typed words (consuming the space, as Backspace
    /// would) and counts an undo of the switched word.
    private func undoAutoSwitch(_ plan: AutoSwitchPlan, proxy: CGEventTapProxy) -> Bool {
        guard buffer.trailingSpaces == 1, buffer.layoutID == plan.target.id else { return false }

        var words = Array(buffer.previousWords.suffix(plan.previousWordCount) + [buffer.current])
        let onScreen = KeyboardLayouts.render(words, with: plan.target, composingDeadKeys: true)
        words[words.count - 1].trailingSpaces = 0
        SyntheticKeyboard.deleteBackward(count: onScreen.count, via: proxy)
        SyntheticKeyboard.type(KeyboardLayouts.render(words, with: plan.source), via: proxy)

        KeyboardLayouts.select(plan.source)
        currentLayout = plan.source
        buffer.deleteBackward()
        buffer.markConverted(to: plan.source.id, includingPrevious: plan.previousWordCount)
        // Saving the undo writes defaults, and every defaults observer would run inside the tap callback.
        DispatchQueue.main.async { [weak self] in
            self?.autoSwitcher.rememberUndo(for: plan)
            self?.onAutoSwitchUndo?()
        }
        return true
    }
}
