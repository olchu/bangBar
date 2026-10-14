import Foundation

@main
struct KeyboardAutoSwitchRulesTests {
    private static let english: Set<String> = ["hello", "hello,", "git", "ok", "vs", "dc§", "dc", ";t", "t"]
    private static let russian: Set<String> = ["привет", "как", "муж", "всё"]
    private static let englishPatterns = bundledPatterns("en")
    private static let russianPatterns = bundledPatterns("ru")

    static func main() {
        check("ghbdtn", "привет", expected: true, "wrong-layout Russian word")
        check("руддщ", "hello", typedLanguage: russian, candidateLanguage: english, expected: true, "wrong-layout English word")
        check("ghbdtn?", "привет,", expected: true, "edge punctuation is ignored")
        check("ve;", "муж", expected: true, "punctuation key that is a letter in the candidate")
        check("hello,", "руддщб", typedLanguage: english, candidateLanguage: russian, expected: false, "valid typed word stays")
        check("руддщб", "hello,", typedLanguage: russian, candidateLanguage: english, expected: true, "typed letter becoming a comma")
        check("git", "пше", expected: false, "valid typed word, invalid candidate")
        check("kubernetes", "лгиуктуеуы", expected: false, "unknown in both dictionaries")
        check("rf", "ка", expected: false, "two letters outside the short-word list")
        check("yt", "не", expected: true, "common two-letter word")
        check(";t", "же", expected: true, "punctuation where the candidate has a letter is not a typed word")
        check("vs", "мы", expected: false, "valid typed two-letter word stays")
        check("dc§", "всё", expected: true, "spell checker skipping punctuation does not count")
        check("z", "я", expected: false, "single letters never convert on their own")
        check(
            "ещё", "to§",
            typedLanguage: russian,
            candidateLanguage: english,
            candidateShortWords: ["to"],
            expected: false,
            "a typed letter at the edge is never dropped"
        )
        check("h2o", "р2щ", expected: false, "digits inside the word")
        check("...", "юют", expected: false, "candidate must be a real word")
        check("", "", expected: false, "empty")
        checkContext("я", expected: true, "single letter before a switched word")
        checkContext("Я", expected: true, "capitalised single letter")
        checkContext("мы", expected: true, "two-letter word before a switched word")
        checkContext("ф", expected: false, "English `a` typed in Russian is not a Russian word")
        checkContext("Ш", expected: false, "English `I` typed in Russian is not a Russian word")
        checkContext("дом", expected: false, "longer words rely on the dictionary")
        checkLetterPatterns()
        checkUnknownWords()
        checkEditDistance()
        print("PASS: keyboard auto-switch rules")
    }

    private static func bundledPatterns(_ language: String) -> KeyboardLetterPatterns {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BangBar/KeyboardImpossibleLetters-\(language).txt")
        guard let patterns = KeyboardLetterPatterns(contentsOf: url) else { fatalError("missing \(url.path)") }
        return patterns
    }

    private static func checkLetterPatterns() {
        for (word, patterns) in [("hello", englishPatterns), ("kubernetes", englishPatterns), ("привет", russianPatterns),
                                 ("закомить", russianPatterns), ("Запушить", russianPatterns)] {
            precondition(patterns.impossibleSpotCount(in: word) == 0, "real word \(word) has impossible letters")
        }
        precondition(englishPatterns.impossibleSpotCount(in: "pfrjvbnm") >= 2, "закомить typed in English")
        precondition(englishPatterns.impossibleSpotCount(in: "GHBDTN") >= 2, "uppercase is compared as lowercase")
        precondition(russianPatterns.impossibleSpotCount(in: "вуздщн") >= 2, "deploy typed in Russian")
        precondition(russianPatterns.impossibleSpotCount(in: "ьныйд") == 1, "a Russian word never starts with ь")
        precondition(KeyboardLetterPatterns(impossible: ["^q", "q$"]).impossibleSpotCount(in: "q") == 2, "word edges")
    }

    private static func checkUnknownWords() {
        checkUnknown("pfrjvbnm", "закомить", expected: true, "slang unknown to both dictionaries")
        checkUnknown("Pfrjvbnm", "Закомить", expected: true, "capitalised word")
        checkUnknown("yjhv", "норм", expected: true, "four letters with impossible spots")
        checkUnknown("вуздщн", "deploy", typedPatterns: russianPatterns, candidatePatterns: englishPatterns,
                     expected: true, "English typed in Russian")
        checkUnknown("cgevent", "спумуте", expected: false, "one impossible spot is not enough")
        checkUnknown("CGEvent", "СПУмуте", candidateDistance: 1, expected: false, "mixed case is an identifier")
        checkUnknown("PFRJVBNM", "ЗАКОМИТЬ", expected: false, "all caps is an acronym")
        checkUnknown("vfr", "мак", expected: false, "three letters are too short")
        checkUnknown("pfrjvbnm", "закомить", candidatePatterns: nil, expected: false, "no table for the candidate")
        checkUnknown("mysql", "ьныйд", typedPatterns: englishPatterns, candidatePatterns: russianPatterns,
                     candidateDistance: 1, expected: false, "candidate with impossible letters")
        checkUnknown("rhby;", "кринж", candidateDistance: 1, expected: true, "one typo from a word")
        checkUnknown("rhby;", "кринж", candidateDistance: 1, typedDistance: 1, expected: false,
                     "typed word is itself one typo from a word")
        checkUnknown("rhby;", "кринж", candidateDistance: 2, expected: false, "candidate two typos from a word")
        checkUnknown("hjr", "рок", candidateDistance: 1, expected: false, "typo rule needs five letters")

        let converts = KeyboardAutoSwitchRules.shouldConvert(
            typed: "pfrjvbnm,".map(String.init),
            candidate: "закомить,".map(String.init).dropLast() + ["б"],
            isTypedValid: { _ in false },
            isCandidateValid: { _ in false },
            isUnknownWordConvertible: { typedCore, candidateCore in typedCore == "pfrjvbnm" && candidateCore == "закомить" }
        )
        precondition(!converts, "a typed comma that becomes a letter is part of the candidate core")
        let convertsCore = KeyboardAutoSwitchRules.shouldConvert(
            typed: "pfrjvbnm?".map(String.init),
            candidate: "закомить,".map(String.init),
            isTypedValid: { _ in false },
            isCandidateValid: { _ in false },
            isUnknownWordConvertible: { typedCore, candidateCore in typedCore == "pfrjvbnm" && candidateCore == "закомить" }
        )
        precondition(convertsCore, "unknown-word evidence receives cores without edge punctuation")
    }

    private static func checkUnknown(
        _ typed: String,
        _ candidate: String,
        typedPatterns: KeyboardLetterPatterns? = englishPatterns,
        candidatePatterns: KeyboardLetterPatterns? = russianPatterns,
        candidateDistance: Int = 3,
        typedDistance: Int = 3,
        expected: Bool,
        _ message: String
    ) {
        let actual = KeyboardAutoSwitchRules.isUnknownWordConvertible(
            typedCore: typed,
            candidateCore: candidate,
            typedPatterns: typedPatterns,
            candidatePatterns: candidatePatterns,
            typedDistance: { _ in typedDistance },
            candidateDistance: { _ in candidateDistance }
        )
        precondition(actual == expected, "\(message): expected \(expected) for \(typed) → \(candidate)")
    }

    private static func checkEditDistance() {
        precondition(KeyboardAutoSwitchRules.editDistance("закомить", "закосить") == 1, "substitution")
        precondition(KeyboardAutoSwitchRules.editDistance("Кринж", "кринжа") == 1, "case-insensitive insertion")
        precondition(KeyboardAutoSwitchRules.editDistance("", "abc") == 3, "empty word")
        precondition(KeyboardAutoSwitchRules.editDistance("kitten", "sitting") == 3, "classic example")
    }

    private static func checkContext(_ candidate: String, expected: Bool, _ message: String) {
        let actual = KeyboardAutoSwitchRules.shouldConvertBeforeSwitchedWord(
            candidate: candidate,
            candidateShortWords: KeyboardAutoSwitchRules.shortWords["ru"] ?? []
        )
        precondition(actual == expected, "\(message): expected \(expected) for \(candidate)")
    }

    private static func check(
        _ typed: String,
        _ candidate: String,
        typedLanguage: Set<String> = english,
        candidateLanguage: Set<String> = russian,
        candidateShortWords: Set<String> = KeyboardAutoSwitchRules.shortWords["ru"] ?? [],
        expected: Bool,
        _ message: String
    ) {
        let actual = KeyboardAutoSwitchRules.shouldConvert(
            typed: typed.map(String.init),
            candidate: candidate.map(String.init),
            candidateShortWords: candidateShortWords,
            isTypedValid: { typedLanguage.contains($0) },
            isCandidateValid: { candidateLanguage.contains($0) }
        )
        precondition(actual == expected, "\(message): expected \(expected) for \(typed) → \(candidate)")
    }
}
