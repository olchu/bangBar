import Foundation

@main
struct KeyboardLearnedWordsTests {
    private static let github = KeyboardLearnedWord(sourceLayoutID: "us", targetLayoutID: "ru", word: "гитхаб")
    private static let deploy = KeyboardLearnedWord(sourceLayoutID: "us", targetLayoutID: "ru", word: "деплой")

    static func main() {
        roundTripsThroughRawValue()
        ignoresMalformedLines()
        reinsertingMovesToTheEnd()
        dropsOldestBeyondCapacity()
        removes()
        coresStripEdgePunctuation()
        typedWordsWithPunctuationInsideAreNotWords()
        print("PASS: keyboard learned words")
    }

    private static func roundTripsThroughRawValue() {
        var learned = KeyboardLearnedWords()
        learned.insert(github)
        learned.insert(deploy)
        let restored = KeyboardLearnedWords(rawValue: learned.rawValue)
        precondition(restored.entries == [github, deploy])
        precondition(restored.contains(github) && restored.words == ["гитхаб", "деплой"])
        precondition(!restored.contains(KeyboardLearnedWord(sourceLayoutID: "ru", targetLayoutID: "us", word: "гитхаб")),
                     "Entries are per layout pair")
    }

    private static func ignoresMalformedLines() {
        let learned = KeyboardLearnedWords(rawValue: "us\tru\tгитхаб\n\nbroken\nus\t\tword\nus\tru\tдеплой")
        precondition(learned.entries == [github, deploy])
    }

    private static func reinsertingMovesToTheEnd() {
        var learned = KeyboardLearnedWords()
        learned.insert(github)
        learned.insert(deploy)
        learned.insert(github)
        precondition(learned.entries == [deploy, github])
    }

    private static func dropsOldestBeyondCapacity() {
        var learned = KeyboardLearnedWords()
        for index in 0...KeyboardLearnedWords.capacity {
            learned.insert(KeyboardLearnedWord(sourceLayoutID: "us", targetLayoutID: "ru", word: "w\(index)"))
        }
        precondition(learned.entries.count == KeyboardLearnedWords.capacity)
        precondition(learned.entries.first?.word == "w1")
    }

    private static func removes() {
        var learned = KeyboardLearnedWords()
        learned.insert(github)
        learned.remove(github)
        learned.remove(deploy)
        precondition(learned.entries.isEmpty && learned.rawValue.isEmpty)
    }

    private static func coresStripEdgePunctuation() {
        let cores = KeyboardAutoSwitchRules.cores(typed: "ufnqf,?".map(String.init), candidate: "гитхаб,".map(String.init))
        precondition(cores?.typed == "ufnqf," && cores?.candidate == "гитхаб")
        precondition(KeyboardAutoSwitchRules.cores(typed: "ещё".map(String.init), candidate: "to§".map(String.init)) == nil)
        precondition(KeyboardAutoSwitchRules.cores(typed: "...".map(String.init), candidate: "...".map(String.init)) == nil)
    }

    private static func typedWordsWithPunctuationInsideAreNotWords() {
        precondition(KeyboardAutoSwitchRules.isWord(typedCore: "hello", isValid: { _ in true }))
        precondition(!KeyboardAutoSwitchRules.isWord(typedCore: "ufnqf,", isValid: { _ in true }))
        precondition(!KeyboardAutoSwitchRules.isWord(typedCore: "ltgkjq", isValid: { _ in false }))
    }
}
