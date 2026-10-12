import Foundation

struct TypedKeystroke: Equatable {
    let keyCode: UInt16
    let shift: Bool
    let capsLock: Bool
}

struct KeyboardWordBuffer {
    private(set) var keystrokes: [TypedKeystroke] = []
    private(set) var trailingSpaces = 0
    private(set) var layoutID: String?

    var isEmpty: Bool { keystrokes.isEmpty }

    mutating func appendCharacter(_ keystroke: TypedKeystroke, layoutID: String) {
        if trailingSpaces > 0 || (self.layoutID != nil && self.layoutID != layoutID) {
            reset()
        }
        if keystrokes.isEmpty {
            self.layoutID = layoutID
        }
        keystrokes.append(keystroke)
    }

    mutating func appendSpace() {
        guard !keystrokes.isEmpty else { return }
        trailingSpaces += 1
    }

    mutating func deleteBackward() {
        if trailingSpaces > 0 {
            trailingSpaces -= 1
        } else if !keystrokes.isEmpty {
            keystrokes.removeLast()
            if keystrokes.isEmpty {
                layoutID = nil
            }
        }
    }

    mutating func markConverted(to layoutID: String) {
        guard !keystrokes.isEmpty else { return }
        self.layoutID = layoutID
    }

    mutating func reset() {
        keystrokes.removeAll()
        trailingSpaces = 0
        layoutID = nil
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
