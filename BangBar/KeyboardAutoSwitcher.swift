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
    private var enabledLayouts: [KeyboardLayout] = []
    private var frontmostBundleID: String?
    private var isSpellCheckerWarm = false
    private lazy var spellCheckerLanguages = Set(NSSpellChecker.shared.availableLanguages)

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: BangBarSettings.Key.keyboardSwitcherAutoEnabled)
    }

    func refreshLayouts() {
        enabledLayouts = KeyboardLayouts.enabled()
    }

    func setFrontmostApp(_ bundleID: String?) {
        frontmostBundleID = bundleID
    }

    /// The first check loads dictionaries; doing it inside the event tap could stall typing long enough
    /// for macOS to disable the tap.
    func warmUpIfNeeded() {
        guard isEnabled, !isSpellCheckerWarm else { return }
        isSpellCheckerWarm = true
        for language in Set(enabledLayouts.compactMap(spellLanguage(for:))) {
            _ = isWord("warmup", language: language)
        }
    }

    func plan(for buffer: KeyboardWordBuffer) -> AutoSwitchPlan? {
        guard isEnabled, !isFrontmostAppExcluded, let sourceID = buffer.layoutID,
              let sourceIndex = enabledLayouts.firstIndex(where: { $0.id == sourceID }) else { return nil }
        let source = enabledLayouts[sourceIndex]
        let sourceLanguage = spellLanguage(for: source)

        let typed = buffer.keystrokes.map { KeyboardLayouts.translate([$0], with: source) }
        let typedWord = typed.joined()
        guard !BangBarSettings.keyboardSwitcherExceptions.contains(typedWord.lowercased()) else { return nil }
        let learnedWords = BangBarSettings.keyboardSwitcherLearnedWords

        for offset in 1..<enabledLayouts.count {
            let target = enabledLayouts[(sourceIndex + offset) % enabledLayouts.count]
            let targetLanguage = spellLanguage(for: target)
            let candidate = buffer.keystrokes.map { KeyboardLayouts.translate([$0], with: target) }
            guard let cores = KeyboardAutoSwitchRules.cores(typed: typed, candidate: candidate) else { continue }

            let learnedWord = KeyboardLearnedWord(
                sourceLayoutID: source.id,
                targetLayoutID: target.id,
                word: cores.candidate.lowercased()
            )
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
            isCandidateValid: { isWord($0, language: targetLanguage) }
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

    /// An undone switch is never repeated: the typed word becomes an exception and stops being learned.
    func rememberException(for plan: AutoSwitchPlan) {
        var exceptions = BangBarSettings.keyboardSwitcherExceptions
        exceptions.insert(plan.typedWord.lowercased())
        BangBarSettings.keyboardSwitcherExceptions = exceptions

        var learnedWords = BangBarSettings.keyboardSwitcherLearnedWords
        learnedWords.remove(plan.learnedWord)
        BangBarSettings.keyboardSwitcherLearnedWords = learnedWords
    }

    /// Learns a word converted by hand (`ufnqf,` → `гитхаб`) so it switches automatically next time.
    /// Converting it back to the layout it was typed in takes the lesson back. Real words in the typed
    /// layout are never learned, so a stray conversion cannot break normal typing.
    func learnManualConversion(of keystrokes: [TypedKeystroke], from originLayoutID: String, to targetLayoutID: String) {
        guard let origin = enabledLayouts.first(where: { $0.id == originLayoutID }) else { return }
        let typed = keystrokes.map { KeyboardLayouts.translate([$0], with: origin) }

        var learnedWords = BangBarSettings.keyboardSwitcherLearnedWords
        for layout in enabledLayouts where layout.id != origin.id {
            if let entry = learnedWord(typed: typed, keystrokes: keystrokes, from: origin, to: layout) {
                learnedWords.remove(entry)
            }
        }
        defer { BangBarSettings.keyboardSwitcherLearnedWords = learnedWords }

        guard targetLayoutID != originLayoutID,
              let target = enabledLayouts.first(where: { $0.id == targetLayoutID }) else { return }
        let candidate = keystrokes.map { KeyboardLayouts.translate([$0], with: target) }
        guard let cores = KeyboardAutoSwitchRules.cores(typed: typed, candidate: candidate),
              cores.candidate.count(where: \.isLetter) >= 2 else { return }
        if let language = spellLanguage(for: origin),
           KeyboardAutoSwitchRules.isWord(typedCore: cores.typed, isValid: { isWord($0, language: language) }) {
            return
        }
        learnedWords.insert(KeyboardLearnedWord(
            sourceLayoutID: origin.id,
            targetLayoutID: target.id,
            word: cores.candidate.lowercased()
        ))

        var exceptions = BangBarSettings.keyboardSwitcherExceptions
        exceptions.remove(typed.joined().lowercased())
        BangBarSettings.keyboardSwitcherExceptions = exceptions
    }

    private func learnedWord(
        typed: [String],
        keystrokes: [TypedKeystroke],
        from origin: KeyboardLayout,
        to target: KeyboardLayout
    ) -> KeyboardLearnedWord? {
        let candidate = keystrokes.map { KeyboardLayouts.translate([$0], with: target) }
        guard let cores = KeyboardAutoSwitchRules.cores(typed: typed, candidate: candidate) else { return nil }
        return KeyboardLearnedWord(sourceLayoutID: origin.id, targetLayoutID: target.id, word: cores.candidate.lowercased())
    }

    private var isFrontmostAppExcluded: Bool {
        guard let frontmostBundleID else { return false }
        return BangBarSettings.keyboardSwitcherExcludedApps.contains(frontmostBundleID)
    }

    private func spellLanguage(for layout: KeyboardLayout) -> String? {
        guard let language = layout.language else { return nil }
        return spellCheckerLanguages.contains(language) ? language : nil
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
