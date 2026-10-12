import Foundation

@main
struct KeyboardWordBufferTests {
    static func main() {
        bufferCollectsWordAndTrailingSpaces()
        bufferStartsNewWordAfterSpace()
        bufferBackspaceRemovesSpacesThenKeys()
        bufferResetsOnLayoutChangeMidWord()
        bufferKeepsKeystrokesAfterConversion()
        bufferKeepsPreviousWordsSeparatedBySpaces()
        bufferBackspaceReturnsToPreviousWord()
        bufferMarksPreviousWordsConverted()
        doubleTapTriggersOnSecondQuickTap()
        doubleTapIgnoresSlowOrHeldTaps()
        doubleTapIgnoresInterruptedTaps()
        print("PASS: keyboard word buffer and double-tap detector")
    }

    private static let g = TypedKeystroke(keyCode: 5, shift: false, capsLock: false)
    private static let h = TypedKeystroke(keyCode: 4, shift: false, capsLock: false)
    private static let b = TypedKeystroke(keyCode: 11, shift: true, capsLock: false)

    private static func bufferCollectsWordAndTrailingSpaces() {
        var buffer = KeyboardWordBuffer()
        buffer.appendSpace()
        precondition(buffer.isEmpty && buffer.trailingSpaces == 0, "Leading space must be ignored")

        buffer.appendCharacter(g, layoutID: "en")
        buffer.appendCharacter(h, layoutID: "en")
        buffer.appendSpace()
        buffer.appendSpace()
        precondition(buffer.keystrokes == [g, h])
        precondition(buffer.trailingSpaces == 2)
        precondition(buffer.layoutID == "en")
    }

    private static func bufferStartsNewWordAfterSpace() {
        var buffer = KeyboardWordBuffer()
        buffer.appendCharacter(g, layoutID: "en")
        buffer.appendSpace()
        buffer.appendCharacter(b, layoutID: "en")
        precondition(buffer.keystrokes == [b])
        precondition(buffer.trailingSpaces == 0)
    }

    private static func bufferBackspaceRemovesSpacesThenKeys() {
        var buffer = KeyboardWordBuffer()
        buffer.appendCharacter(g, layoutID: "en")
        buffer.appendCharacter(h, layoutID: "en")
        buffer.appendSpace()
        buffer.deleteBackward()
        precondition(buffer.keystrokes == [g, h] && buffer.trailingSpaces == 0)
        buffer.deleteBackward()
        precondition(buffer.keystrokes == [g])
        buffer.deleteBackward()
        precondition(buffer.isEmpty && buffer.layoutID == nil)
        buffer.deleteBackward()
        precondition(buffer.isEmpty)
    }

    private static func bufferResetsOnLayoutChangeMidWord() {
        var buffer = KeyboardWordBuffer()
        buffer.appendCharacter(g, layoutID: "en")
        buffer.appendCharacter(h, layoutID: "ru")
        precondition(buffer.keystrokes == [h])
        precondition(buffer.layoutID == "ru")
    }

    private static func bufferKeepsKeystrokesAfterConversion() {
        var buffer = KeyboardWordBuffer()
        buffer.appendCharacter(g, layoutID: "en")
        buffer.appendCharacter(h, layoutID: "en")
        buffer.appendSpace()
        buffer.markConverted(to: "ru")
        precondition(buffer.keystrokes == [g, h] && buffer.trailingSpaces == 1)
        precondition(buffer.layoutID == "ru")

        buffer.deleteBackward()
        buffer.appendCharacter(b, layoutID: "ru")
        precondition(buffer.keystrokes == [g, h, b], "Typing on in the converted layout continues the word")
    }

    private static func bufferKeepsPreviousWordsSeparatedBySpaces() {
        var buffer = KeyboardWordBuffer()
        for _ in 0..<5 {
            buffer.appendCharacter(g, layoutID: "en")
            buffer.appendSpace()
        }
        buffer.appendCharacter(h, layoutID: "en")
        precondition(buffer.previousWords.count == KeyboardWordBuffer.maxPreviousWords, "History is capped")
        precondition(buffer.previousWords.allSatisfy { $0.keystrokes == [g] && $0.trailingSpaces == 1 })
        precondition(buffer.keystrokes == [h])

        buffer.appendCharacter(b, layoutID: "ru")
        precondition(buffer.previousWords.isEmpty && buffer.keystrokes == [b], "A layout change mid-word drops the history")

        buffer.appendSpace()
        buffer.reset()
        precondition(buffer.previousWords.isEmpty && buffer.isEmpty)
    }

    private static func bufferBackspaceReturnsToPreviousWord() {
        var buffer = KeyboardWordBuffer()
        buffer.appendCharacter(g, layoutID: "en")
        buffer.appendSpace()
        buffer.appendCharacter(h, layoutID: "en")
        buffer.deleteBackward()
        precondition(buffer.keystrokes == [g] && buffer.trailingSpaces == 1, "Deleting a word restores the one before it")
        precondition(buffer.previousWords.isEmpty)
        buffer.appendCharacter(b, layoutID: "en")
        precondition(buffer.previousWords.map(\.keystrokes) == [[g]] && buffer.keystrokes == [b])
    }

    private static func bufferMarksPreviousWordsConverted() {
        var buffer = KeyboardWordBuffer()
        for key in [g, h, b] {
            buffer.appendCharacter(key, layoutID: "en")
            buffer.appendSpace()
        }
        buffer.appendCharacter(g, layoutID: "en")
        buffer.markConverted(to: "ru", includingPrevious: 2)
        precondition(buffer.previousWords.map(\.layoutID) == ["en", "ru", "ru"])
        precondition(buffer.layoutID == "ru")
    }

    private static func doubleTapTriggersOnSecondQuickTap() {
        var detector = DoubleTapDetector()
        detector.press(at: 0)
        precondition(!detector.release(at: 0.08))
        detector.press(at: 0.2)
        precondition(detector.release(at: 0.28))

        detector.press(at: 0.5)
        precondition(!detector.release(at: 0.55), "A third tap starts a new sequence")
    }

    private static func doubleTapIgnoresSlowOrHeldTaps() {
        var detector = DoubleTapDetector()
        detector.press(at: 0)
        precondition(!detector.release(at: 0.05))
        detector.press(at: 0.6)
        precondition(!detector.release(at: 0.65), "Taps too far apart must not trigger")

        var held = DoubleTapDetector()
        held.press(at: 0)
        precondition(!held.release(at: 0.05))
        held.press(at: 0.1)
        precondition(!held.release(at: 0.5), "A long hold is not a tap")
    }

    private static func doubleTapIgnoresInterruptedTaps() {
        var detector = DoubleTapDetector()
        detector.press(at: 0)
        precondition(!detector.release(at: 0.05))
        detector.press(at: 0.1)
        detector.interrupt()
        precondition(!detector.release(at: 0.15), "Shift used for a capital letter must not trigger")

        detector.press(at: 0.2)
        precondition(!detector.release(at: 0.25))
        detector.interrupt()
        detector.press(at: 0.3)
        precondition(!detector.release(at: 0.35), "A key between taps cancels the sequence")
    }
}
