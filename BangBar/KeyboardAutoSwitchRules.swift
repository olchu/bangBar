import Foundation

enum KeyboardAutoSwitchRules {
    static let minimumLetters = 3
    private static let sentencePunctuation: Set<String> = [",", ".", ";", ":", "!", "?", "'", "\"", "(", ")"]

    /// One- and two-letter words are too ambiguous for dictionaries alone, so they convert only into these
    /// common words: two-letter ones on their own, single letters only next to a switched word.
    static let shortWords: [String: Set<String>] = [
        "ru": [
            "я", "в", "с", "к", "у", "о", "и", "а",
            "не", "на", "но", "да", "он", "мы", "вы", "ты", "то", "же", "ли", "бы", "по", "за",
            "из", "от", "до", "во", "ко", "со", "её", "ей", "им", "их", "ни", "уж", "ну"
        ],
        "en": [
            "i", "a",
            "it", "is", "in", "to", "on", "of", "we", "me", "my", "he", "be", "by", "do", "go",
            "so", "no", "up", "us", "an", "as", "at", "if", "or", "am", "hi"
        ]
    ]

    /// `typed` and `candidate` hold one string per keystroke: what each key produced in the layout the word
    /// was typed in, and what it would produce in the candidate layout.
    /// Converts only when the typed word is not a word but its candidate is, so unknown words stay untouched.
    static func shouldConvert(
        typed: [String],
        candidate: [String],
        candidateShortWords: Set<String> = [],
        isTypedValid: (String) -> Bool,
        isCandidateValid: (String) -> Bool
    ) -> Bool {
        guard typed.count == candidate.count,
              let first = candidate.firstIndex(where: { isLetter($0) }),
              let last = candidate.lastIndex(where: { isLetter($0) }) else { return false }

        // Keys outside the candidate's letters are edge punctuation (`ghbdtn?` → `привет,`, `руддщб` → `hello,`)
        // and are not spell-checked. A typed letter may only become sentence punctuation there; otherwise
        // `ещё` would lose its `ё` to `§` and be judged as `to`.
        for index in Array(0..<first) + Array((last + 1)..<typed.count)
        where isLetter(typed[index]) && !sentencePunctuation.contains(candidate[index]) {
            return false
        }
        let candidateCore = candidate[first...last].joined()
        guard candidateCore.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return false }

        // The spell checker skips punctuation, so `dc§` (`всё`) would pass as `dc`. A real word has no
        // punctuation where the other layout has letters.
        let typedCore = typed[first...last].joined()
        let isTypedWord = typedCore.allSatisfy { $0.isLetter || $0 == "-" } && isTypedValid(typedCore)
        guard !isTypedWord else { return false }

        let letterCount = candidateCore.count(where: \.isLetter)
        if letterCount >= minimumLetters {
            return isCandidateValid(candidateCore)
        }
        return letterCount == 2 && candidateShortWords.contains(candidateCore.lowercased())
    }

    /// A word right before an automatically switched one converts with it when it becomes a common short word
    /// (`z ntz` → `я тебя`): the switched word is the evidence a dictionary cannot give for `z` alone.
    static func shouldConvertBeforeSwitchedWord(candidate: String, candidateShortWords: Set<String>) -> Bool {
        candidateShortWords.contains(candidate.lowercased())
    }

    private static func isLetter(_ keyOutput: String) -> Bool {
        keyOutput.count == 1 && keyOutput.first?.isLetter == true
    }
}
