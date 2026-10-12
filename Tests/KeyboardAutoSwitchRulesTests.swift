import Foundation

@main
struct KeyboardAutoSwitchRulesTests {
    private static let english: Set<String> = ["hello", "hello,", "git", "ok", "vs", "dc§", "dc", ";t", "t"]
    private static let russian: Set<String> = ["привет", "как", "муж", "всё"]

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
        print("PASS: keyboard auto-switch rules")
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
