import Foundation

struct TypedKeystroke: Equatable {
    let keyCode: UInt16
    let shift: Bool
    let capsLock: Bool
}

struct TypedWord: Equatable {
    var keystrokes: [TypedKeystroke] = []
    var layoutID: String?
    var trailingSpaces = 0
}

struct KeyboardWordBuffer {
    static let maxPreviousWords = 3

    /// Earlier words separated from the current one only by spaces, oldest first. Lets an automatic switch
    /// also fix short words before it (`z ntz` → `я тебя`). Empty whenever the current word is empty.
    private(set) var previousWords: [TypedWord] = []
    private(set) var current = TypedWord()

    var keystrokes: [TypedKeystroke] { current.keystrokes }
    var trailingSpaces: Int { current.trailingSpaces }
    var layoutID: String? { current.layoutID }
    var isEmpty: Bool { current.keystrokes.isEmpty }

    mutating func appendCharacter(_ keystroke: TypedKeystroke, layoutID: String) {
        if current.trailingSpaces > 0 {
            previousWords = Array((previousWords + [current]).suffix(Self.maxPreviousWords))
            current = TypedWord()
        } else if current.layoutID != nil && current.layoutID != layoutID {
            reset()
        }
        if current.keystrokes.isEmpty {
            current.layoutID = layoutID
        }
        current.keystrokes.append(keystroke)
    }

    mutating func appendSpace() {
        guard !current.keystrokes.isEmpty else { return }
        current.trailingSpaces += 1
    }

    mutating func deleteBackward() {
        if current.trailingSpaces > 0 {
            current.trailingSpaces -= 1
        } else if !current.keystrokes.isEmpty {
            current.keystrokes.removeLast()
            if current.keystrokes.isEmpty {
                current = previousWords.popLast() ?? TypedWord()
            }
        }
    }

    mutating func markConverted(to layoutID: String, includingPrevious previousCount: Int = 0) {
        guard !current.keystrokes.isEmpty else { return }
        current.layoutID = layoutID
        for index in previousWords.indices.suffix(previousCount) {
            previousWords[index].layoutID = layoutID
        }
    }

    mutating func reset() {
        previousWords.removeAll()
        current = TypedWord()
    }
}

struct DoubleTapDetector {
    var maxInterval: TimeInterval = 0.4
    var maxHold: TimeInterval = 0.3

    private var pressedAt: TimeInterval?
    private var lastTapAt: TimeInterval?

    mutating func press(at time: TimeInterval) {
        pressedAt = time
    }

    mutating func release(at time: TimeInterval) -> Bool {
        guard let pressedAt else { return false }
        self.pressedAt = nil
        guard time - pressedAt <= maxHold else {
            lastTapAt = nil
            return false
        }
        if let lastTapAt, time - lastTapAt <= maxInterval {
            self.lastTapAt = nil
            return true
        }
        lastTapAt = time
        return false
    }

    mutating func interrupt() {
        pressedAt = nil
        lastTapAt = nil
    }
}
