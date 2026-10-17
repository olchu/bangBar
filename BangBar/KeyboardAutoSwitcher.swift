import AppKit

struct AutoSwitchPlan {
    let source: KeyboardLayout
    let target: KeyboardLayout
    let typedWord: String
    /// This conversion as a learned-word entry, so undoing it can forget a learned word.
    let learnedWord: KeyboardLearnedWord
    /// Short words right before the current one that switch along with it (`z` in `z ntz` → `я тебя`).
    let previousWordCount: Int
}

/// Decides whether a just-finished word was typed in the wrong layout, using the system spell checker and
/// the words the user converted by hand.
final class KeyboardAutoSwitcher {
    static let undosBeforeException = 5

    private(set) var enabledLayouts: [KeyboardLayout] = []
    private var frontmostBundleID: String?
    private var preparedLanguages: Set<String> = []
    private lazy var spellCheckerLanguages = Set(NSSpellChecker.shared.availableLanguages)
    private var letterPatterns: [String: KeyboardLetterPatterns] = [:]

    // Cached from UserDefaults by `reloadSettings()`: `plan(for:)` runs inside the event tap on every Space.
    private(set) var isEnabled = false
    private var excludedApps: Set<String> = []
    private var exceptions: Set<String> = []
    private var undoCounts: [String: Int] = [:]
    private var learnedWords = KeyboardLearnedWords()

    func refreshLayouts() {
        enabledLayouts = KeyboardLayouts.enabled()
        prepareLanguagesIfNeeded()
    }

    func layout(withID id: String) -> KeyboardLayout? {
        enabledLayouts.first { $0.id == id }
    }

    func reloadSettings() {
        isEnabled = UserDefaults.standard.bool(forKey: BangBarSettings.Key.keyboardSwitcherAutoEnabled)
        excludedApps = Set(BangBarSettings.keyboardSwitcherExcludedApps)
        exceptions = BangBarSettings.keyboardSwitcherExceptions
        undoCounts = BangBarSettings.keyboardSwitcherUndoCounts
        learnedWords = BangBarSettings.keyboardSwitcherLearnedWords
    }

    func setFrontmostApp(_ bundleID: String?) {
        frontmostBundleID = bundleID
    }

    private var isFrontmostAppExcluded: Bool {
        frontmostBundleID.map(excludedApps.contains) ?? false
    }

    /// The first check of a language loads its dictionary; doing it inside the event tap could stall typing
    /// long enough for macOS to disable the tap.
    func prepareLanguagesIfNeeded() {
        guard isEnabled else { return }
        for language in Set(enabledLayouts.compactMap(spellLanguage(for:))) where !preparedLanguages.contains(language) {
            preparedLanguages.insert(language)
            _ = isWord("warmup", language: language)
            _ = nearestWordDistance("warmupp", language: language)
            letterPatterns[language] = KeyboardLetterPatterns.bundled(language: language)
        }
    }

    func plan(for buffer: KeyboardWordBuffer) -> AutoSwitchPlan? {
        guard isEnabled, !isFrontmostAppExcluded, let sourceID = buffer.layoutID,
              let sourceIndex = enabledLayouts.firstIndex(where: { $0.id == sourceID }) else { return nil }
        let source = enabledLayouts[sourceIndex]
        let sourceLanguage = spellLanguage(for: source)

        let typed = keyOutputs(buffer.keystrokes, in: source)
        let typedWord = typed.joined()
        guard !exceptions.contains(typedWord.lowercased()) else { return nil }

        for offset in 1..<enabledLayouts.count {
            let target = enabledLayouts[(sourceIndex + offset) % enabledLayouts.count]
            let targetLanguage = spellLanguage(for: target)
            let candidate = keyOutputs(buffer.keystrokes, in: target)
            guard let cores = KeyboardAutoSwitchRules.cores(typed: typed, candidate: candidate) else { continue }

            let learnedWord = KeyboardLearnedWord(from: source, to: target, candidateCore: cores.candidate)
            let isConvertible = learnedWords.contains(learnedWord) || isDictionaryConversion(
                typed: typed,
                candidate: candidate,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
            if isConvertible {
                return AutoSwitchPlan(
                    source: source,
                    target: target,
                    typedWord: typedWord,
                    learnedWord: learnedWord,
                    previousWordCount: previousWordCount(in: buffer, from: source, to: target, language: targetLanguage)
                )
            }
        }
        return nil
    }

    private func isDictionaryConversion(
        typed: [String],
        candidate: [String],
        sourceLanguage: String?,
        targetLanguage: String?
    ) -> Bool {
        guard let sourceLanguage, let targetLanguage, sourceLanguage != targetLanguage else { return false }
        return KeyboardAutoSwitchRules.shouldConvert(
            typed: typed,
            candidate: candidate,
            candidateShortWords: KeyboardAutoSwitchRules.shortWords[targetLanguage] ?? [],
            isTypedValid: { isWord($0, language: sourceLanguage) },
            isCandidateValid: { isWord($0, language: targetLanguage) },
            isUnknownWordConvertible: { typedCore, candidateCore in
                KeyboardAutoSwitchRules.isUnknownWordConvertible(
                    typedCore: typedCore,
                    candidateCore: candidateCore,
                    typedPatterns: letterPatterns[sourceLanguage],
                    candidatePatterns: letterPatterns[targetLanguage],
                    typedDistance: { nearestWordDistance($0, language: sourceLanguage) },
                    candidateDistance: { nearestWordDistance($0, language: targetLanguage) }
                )
            }
        )
    }

    private func previousWordCount(
        in buffer: KeyboardWordBuffer,
        from source: KeyboardLayout,
        to target: KeyboardLayout,
        language: String?
    ) -> Int {
        let shortWords = language.flatMap { KeyboardAutoSwitchRules.shortWords[$0] } ?? []
        var count = 0
        for word in buffer.previousWords.reversed() {
            let candidate = KeyboardLayouts.translate(word.keystrokes, with: target)
            guard word.layoutID == source.id,
                  KeyboardAutoSwitchRules.shouldConvertBeforeSwitchedWord(candidate: candidate, candidateShortWords: shortWords)
            else { break }
            count += 1
        }
        return count
    }

    /// A single undo can be a slip, so only the `undosBeforeException`-th undo of the same typed word
    /// stops switching it: the word becomes an exception and stops being learned.
    func rememberUndo(for plan: AutoSwitchPlan) {
        let word = plan.typedWord.lowercased()
        var updatedUndoCounts = undoCounts
        let count = (updatedUndoCounts[word] ?? 0) + 1
        var updatedExceptions = exceptions
        var updatedLearnedWords = learnedWords
        if count >= Self.undosBeforeException {
            updatedUndoCounts[word] = nil
            updatedExceptions.insert(word)
            updatedLearnedWords.remove(plan.learnedWord)
        } else {
            updatedUndoCounts[word] = count
        }
        save(exceptions: updatedExceptions, undoCounts: updatedUndoCounts, learnedWords: updatedLearnedWords)
    }

    /// Writes only what changed: every defaults write makes the whole app re-read its settings.
    private func save(
        exceptions updatedExceptions: Set<String>,
        undoCounts updatedUndoCounts: [String: Int],
        learnedWords updatedLearnedWords: KeyboardLearnedWords
    ) {
        if updatedExceptions != exceptions {
            exceptions = updatedExceptions
            BangBarSettings.keyboardSwitcherExceptions = updatedExceptions
        }
        if updatedUndoCounts != undoCounts {
            undoCounts = updatedUndoCounts
            BangBarSettings.keyboardSwitcherUndoCounts = updatedUndoCounts
        }
        if updatedLearnedWords != learnedWords {
            learnedWords = updatedLearnedWords
            BangBarSettings.keyboardSwitcherLearnedWords = updatedLearnedWords
        }
    }

    /// Learns a word converted by hand (`ufnqf,` → `гитхаб`) so it switches automatically next time.
    /// Converting it back to the layout it was typed in takes the lesson back. Real words in the typed
    /// layout are never learned, so a stray conversion cannot break normal typing.
    func learnManualConversion(of keystrokes: [TypedKeystroke], from originLayoutID: String, to targetLayoutID: String) {
        guard let origin = layout(withID: originLayoutID) else { return }
        let typed = keyOutputs(keystrokes, in: origin)

        var updatedLearnedWords = learnedWords
        var updatedExceptions = exceptions
        var updatedUndoCounts = undoCounts
        for other in enabledLayouts where other.id != origin.id {
            if let cores = KeyboardAutoSwitchRules.cores(typed: typed, candidate: keyOutputs(keystrokes, in: other)) {
                updatedLearnedWords.remove(KeyboardLearnedWord(from: origin, to: other, candidateCore: cores.candidate))
            }
        }
        defer { save(exceptions: updatedExceptions, undoCounts: updatedUndoCounts, learnedWords: updatedLearnedWords) }

        guard targetLayoutID != originLayoutID, let target = layout(withID: targetLayoutID),
              let cores = KeyboardAutoSwitchRules.cores(typed: typed, candidate: keyOutputs(keystrokes, in: target)),
              cores.candidate.count(where: \.isLetter) >= 2 else { return }
        if let language = spellLanguage(for: origin),
           KeyboardAutoSwitchRules.isWord(typedCore: cores.typed, isValid: { isWord($0, language: language) }) {
            return
        }
        updatedLearnedWords.insert(KeyboardLearnedWord(from: origin, to: target, candidateCore: cores.candidate))
        let typedWord = typed.joined().lowercased()
        updatedExceptions.remove(typedWord)
        updatedUndoCounts[typedWord] = nil
    }

    /// One output per key, so `KeyboardAutoSwitchRules.cores` can line up the typed word with a candidate.
    private func keyOutputs(_ keystrokes: [TypedKeystroke], in layout: KeyboardLayout) -> [String] {
        keystrokes.map { KeyboardLayouts.translate([$0], with: layout) }
    }

    private func spellLanguage(for layout: KeyboardLayout) -> String? {
        guard let language = layout.language else { return nil }
        return spellCheckerLanguages.contains(language) ? language : nil
    }

    /// Spell-checker guesses take 5–20 ms, so this only runs for words neither dictionary knows.
    private func nearestWordDistance(_ word: String, language: String) -> Int {
        let range = NSRange(location: 0, length: (word as NSString).length)
        let guesses = NSSpellChecker.shared.guesses(
            forWordRange: range,
            in: word,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        return guesses.map { KeyboardAutoSwitchRules.editDistance(word, $0) }.min() ?? .max
    }

    private func isWord(_ word: String, language: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        ).location == NSNotFound
    }
}

private extension KeyboardLearnedWord {
    init(from source: KeyboardLayout, to target: KeyboardLayout, candidateCore: String) {
        self.init(sourceLayoutID: source.id, targetLayoutID: target.id, word: candidateCore.lowercased())
    }
}
