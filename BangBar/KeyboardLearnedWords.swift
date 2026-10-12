import Foundation

struct KeyboardLearnedWord: Hashable {
    let sourceLayoutID: String
    let targetLayoutID: String
    /// The converted word without edge punctuation, lowercased (`гитхаб`).
    let word: String
}

/// Words the user converted by hand, switched automatically from then on. Stored oldest first, one
/// tab-separated `source target word` entry per line.
struct KeyboardLearnedWords {
    static let capacity = 500

    private(set) var entries: [KeyboardLearnedWord] = []

    init(rawValue: String = "") {
        entries = rawValue.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty }) else { return nil }
            return KeyboardLearnedWord(sourceLayoutID: fields[0], targetLayoutID: fields[1], word: fields[2])
        }
    }

    var rawValue: String {
        entries.map { "\($0.sourceLayoutID)\t\($0.targetLayoutID)\t\($0.word)" }.joined(separator: "\n")
    }

    var words: [String] { entries.map(\.word) }

    func contains(_ entry: KeyboardLearnedWord) -> Bool {
        entries.contains(entry)
    }

    /// Re-learning a word moves it to the end, so the least recently learned words drop out first.
    mutating func insert(_ entry: KeyboardLearnedWord) {
        remove(entry)
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    mutating func remove(_ entry: KeyboardLearnedWord) {
        entries.removeAll { $0 == entry }
    }
}
