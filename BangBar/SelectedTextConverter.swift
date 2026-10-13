import AppKit
import ApplicationServices
import Carbon

enum SelectedTextConverter {
    private static let maxReselectLength = 1_000
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Copies the selection, pastes it converted to the next layout, reselects it, and restores the pasteboard.
    /// Returns the layout the text was converted to, or nil when nothing was converted.
    static func convertSelection() async -> KeyboardLayout? {
        let selectionLength = focusedSelectionLength()
        guard selectionLength != 0 else { return nil }
        let layouts = KeyboardLayouts.enabled()
        guard layouts.count > 1 else { return nil }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let initialChangeCount = pasteboard.changeCount
        ClipboardHistoryService.suspendCapture()
        defer { ClipboardHistoryService.resumeCapture() }

        SyntheticKeyboard.press(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        guard await waitForChange(of: pasteboard, since: initialChangeCount) else { return nil }

        // Editors like VS Code and JetBrains copy the whole line when nothing is selected.
        // Without Accessibility to confirm a selection, a copied full line is treated as no selection.
        guard let text = pasteboard.string(forType: .string), !text.isEmpty,
              selectionLength != nil || !text.hasSuffix("\n"),
              let pair = KeyboardLayouts.conversionPair(for: text, among: layouts) else {
            snapshot.restore(to: pasteboard)
            return nil
        }
        let converted = KeyboardLayouts.convert(text, from: pair.source, to: pair.target)

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        pasteboard.setData(Data(), forType: transientType)
        SyntheticKeyboard.press(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        if converted.count <= maxReselectLength {
            SyntheticKeyboard.selectBackward(count: converted.count)
        }
        KeyboardLayouts.select(pair.target)

        // The app reads the pasteboard when it handles ⌘V; restoring earlier would paste the old contents.
        try? await Task.sleep(for: .milliseconds(400))
        snapshot.restore(to: pasteboard)
        return pair.target
    }

    /// nil when the focused app does not expose its selection through Accessibility (many Electron apps and web views).
    private static func focusedSelectionLength() -> Int? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.length
    }

    private static func waitForChange(of pasteboard: NSPasteboard, since changeCount: Int) async -> Bool {
        for _ in 0..<25 {
            if pasteboard.changeCount != changeCount {
                // changeCount bumps on clearContents, before the app has finished writing its data.
                try? await Task.sleep(for: .milliseconds(50))
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

private struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
