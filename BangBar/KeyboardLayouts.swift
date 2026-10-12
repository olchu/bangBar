import Carbon
import Foundation

struct KeyboardLayout {
    let source: TISInputSource
    let id: String
    let name: String
    let language: String?
    let layoutData: Data
}

enum KeyboardLayouts {
    static func enabled() -> [KeyboardLayout] {
        let filter = [
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { layout(from: $0) }
    }

    static func current() -> KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return layout(from: source)
    }

    static func select(_ layout: KeyboardLayout) {
        TISSelectInputSource(layout.source)
    }

    static func isPrintable(_ keystroke: TypedKeystroke, in layout: KeyboardLayout) -> Bool {
        guard let scalar = translate([keystroke], with: layout).unicodeScalars.first else { return false }
        let isFunctionKey = (0xF700...0xF8FF).contains(scalar.value)
        return !isFunctionKey && !CharacterSet.controlCharacters.contains(scalar)
    }

    /// With `composingDeadKeys`, accent keys combine with the next key the way they do on screen
    /// (`'` + `e` → `é` in U.S. International), so the result matches what the app displays.
    /// A dead key still pending at the end counts as one displayed character.
    static func translate(
        _ keystrokes: [TypedKeystroke],
        with layout: KeyboardLayout,
        composingDeadKeys: Bool = false
    ) -> String {
        layout.layoutData.withUnsafeBytes { raw -> String in
            guard let keyboardLayout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return "" }
            let options = composingDeadKeys ? 0 : OptionBits(kUCKeyTranslateNoDeadKeysMask)
            var deadKeyState: UInt32 = 0
            var isDeadKeyPending = false
            var result = ""
            for keystroke in keystrokes {
                var modifiers = 0
                if keystroke.shift { modifiers |= shiftKey }
                if keystroke.capsLock { modifiers |= alphaLock }
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    keyboardLayout,
                    keystroke.keyCode,
                    UInt16(kUCKeyActionDown),
                    UInt32((modifiers >> 8) & 0xFF),
                    UInt32(LMGetKbdType()),
                    options,
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
                guard status == noErr else { continue }
                isDeadKeyPending = length == 0
                result += String(utf16CodeUnits: characters, count: length)
            }
            if isDeadKeyPending {
                result += " "
            }
            return result
        }
    }

    static func render(_ words: [TypedWord], with layout: KeyboardLayout, composingDeadKeys: Bool = false) -> String {
        words.map { word in
            translate(word.keystrokes, with: layout, composingDeadKeys: composingDeadKeys)
                + String(repeating: " ", count: word.trailingSpaces)
        }.joined()
    }

    /// Picks the layout most of the text's letters were typed in, and the next enabled layout after it.
    static func conversionPair(for text: String, among layouts: [KeyboardLayout]) -> (source: KeyboardLayout, target: KeyboardLayout)? {
        guard layouts.count > 1 else { return nil }
        let letters = text.filter(\.isLetter)
        let scores = layouts.map { layout in
            let map = characterMap(for: layout)
            return letters.count { map[$0] != nil }
        }
        guard let best = scores.max(), best > 0, let sourceIndex = scores.firstIndex(of: best) else { return nil }
        return (layouts[sourceIndex], layouts[(sourceIndex + 1) % layouts.count])
    }

    /// Characters the source layout cannot type (digits keep their keys, emoji, line breaks) are kept as is.
    static func convert(_ text: String, from source: KeyboardLayout, to target: KeyboardLayout) -> String {
        let map = characterMap(for: source)
        var result = ""
        for character in text {
            if let keystroke = map[character] {
                result += translate([keystroke], with: target)
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static let keypadKeyCodes = 65...92

    private static func characterMap(for layout: KeyboardLayout) -> [Character: TypedKeystroke] {
        var map: [Character: TypedKeystroke] = [:]
        for shift in [false, true] {
            for keyCode in UInt16(0)..<128 where !keypadKeyCodes.contains(Int(keyCode)) {
                let keystroke = TypedKeystroke(keyCode: keyCode, shift: shift, capsLock: false)
                guard isPrintable(keystroke, in: layout) else { continue }
                let text = translate([keystroke], with: layout)
                guard text.count == 1, let character = text.first, map[character] == nil else { continue }
                map[character] = keystroke
            }
        }
        return map
    }

    private static func layout(from source: TISInputSource) -> KeyboardLayout? {
        guard let id = stringProperty(source, kTISPropertyInputSourceID),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .map { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] ?? [] }
        return KeyboardLayout(source: source, id: id, name: name, language: languages?.first, layoutData: data)
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
