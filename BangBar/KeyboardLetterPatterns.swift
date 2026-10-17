import Foundation

/// Letter pairs and triples a language never uses (`qz`, `vbn` in English; `ъь`, a word starting with `ь` in
/// Russian). `^` and `$` mark the start and end of a word. The tables are generated from word lists by
/// `scripts/build_keyboard_letter_patterns.py`.
nonisolated struct KeyboardLetterPatterns {
    private let impossible: Set<String>

    init(impossible: Set<String>) {
        self.impossible = impossible
    }

    init?(contentsOf url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let grams = text.split(separator: "\n")
            .filter { !$0.hasPrefix("#") }
            .flatMap { $0.split(separator: " ").map(String.init) }
        guard !grams.isEmpty else { return nil }
        self.init(impossible: Set(grams))
    }

    static func bundled(language: String) -> KeyboardLetterPatterns? {
        Bundle.main.url(forResource: "KeyboardImpossibleLetters-\(language)", withExtension: "txt")
            .flatMap(KeyboardLetterPatterns.init(contentsOf:))
    }

    /// How many letter pairs and triples in `word` never occur in this language: `pfrjvbnm` (`закомить` typed
    /// in English) has several, real words and names have none.
    func impossibleSpotCount(in word: String) -> Int {
        let characters = Array("^" + word.lowercased() + "$")
        var count = 0
        for length in 2...3 where characters.count >= length {
            for start in 0...(characters.count - length)
            where impossible.contains(String(characters[start..<(start + length)])) {
                count += 1
            }
        }
        return count
    }
}
