import AppKit

struct AutoSwitchPlan {
    let source: KeyboardLayout
    let target: KeyboardLayout
    let typedWord: String
    /// Short words right before the current one that switch along with it (`z` in `z ntz` → `я тебя`).
    let previousWordCount: Int
}

/// Decides whether a just-finished word was typed in the wrong layout, using the system spell checker.
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
        guard let sourceLanguage = spellLanguage(for: source) else { return nil }

        let typed = buffer.keystrokes.map { KeyboardLayouts.translate([$0], with: source) }
        let typedWord = typed.joined()
        guard !BangBarSettings.keyboardSwitcherExceptions.contains(typedWord.lowercased()) else { return nil }

        for offset in 1..<enabledLayouts.count {
            let target = enabledLayouts[(sourceIndex + offset) % enabledLayouts.count]
            guard let targetLanguage = spellLanguage(for: target), targetLanguage != sourceLanguage else { continue }
            let candidate = buffer.keystrokes.map { KeyboardLayouts.translate([$0], with: target) }
            let shouldConvert = KeyboardAutoSwitchRules.shouldConvert(
                typed: typed,
                candidate: candidate,
                candidateShortWords: KeyboardAutoSwitchRules.shortWords[targetLanguage] ?? [],
                isTypedValid: { isWord($0, language: sourceLanguage) },
                isCandidateValid: { isWord($0, language: targetLanguage) }
            )
            if shouldConvert {
                return AutoSwitchPlan(
                    source: source,
                    target: target,
                    typedWord: typedWord,
                    previousWordCount: previousWordCount(in: buffer, from: source, to: target, language: targetLanguage)
                )
            }
        }
        return nil
    }

    private func previousWordCount(
        in buffer: KeyboardWordBuffer,
        from source: KeyboardLayout,
        to target: KeyboardLayout,
        language: String
    ) -> Int {
        let shortWords = KeyboardAutoSwitchRules.shortWords[language] ?? []
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

    func rememberException(_ word: String) {
        var exceptions = BangBarSettings.keyboardSwitcherExceptions
        exceptions.insert(word.lowercased())
        BangBarSettings.keyboardSwitcherExceptions = exceptions
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
