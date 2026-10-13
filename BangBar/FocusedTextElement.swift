import AppKit
import ApplicationServices

/// The caret's line and the frame of the field it is in, in Accessibility coordinates
/// (origin at the top-left of the primary screen).
struct TextCaret {
    let line: CGRect
    let field: CGRect?
}

/// The focused text field as Accessibility sees it; nil wherever the app does not expose it
/// (many Electron apps and web views).
enum FocusedTextElement {
    private static let messagingTimeout: Float = 0.25
    /// Some apps report the whole document or a zero rect for the caret; a taller "line" is not a caret.
    private static let maximumCaretHeight: CGFloat = 200

    static func selectedRange() -> CFRange? {
        focusedElement().flatMap(selectedRange(of:))
    }

    /// Blocks on IPC with the focused app, so call it off the main thread.
    static func caret() -> TextCaret? {
        guard let element = focusedElement(), let line = caretLine(in: element) else { return nil }
        return TextCaret(line: line, field: frame(of: element))
    }

    private static func caretLine(in element: AXUIElement) -> CGRect? {
        guard let range = selectedRange(of: element) else { return nil }
        let caret = range.location + range.length
        if let bounds = bounds(of: CFRange(location: caret, length: 0), in: element) {
            return bounds
        }
        // Many apps return nothing for an empty range, so fall back to the character before the caret.
        guard caret > 0, let previous = bounds(of: CFRange(location: caret - 1, length: 1), in: element) else { return nil }
        return CGRect(x: previous.maxX, y: previous.minY, width: 0, height: previous.height)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.height > 0, rect.height <= maximumCaretHeight else { return nil }
        return rect
    }
}
