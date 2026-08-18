import Combine
import SwiftUI
import Translation

struct TranslatorWidget: View {
    let isPanelExpanded: Bool

    @AppStorage(BangBarSettings.Key.translatorSourceIsRussian) private var sourceIsRussian = true
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var errorMessage: String?
    @State private var configuration: TranslationSession.Configuration?
    @State private var isTranslating = false
    @FocusState private var isInputFocused: Bool

    private var accentColor: Color { Color(hex: accentColorHex) }
    private var sourceLanguage: Locale.Language { Locale.Language(identifier: sourceIsRussian ? "ru" : "en") }
    private var targetLanguage: Locale.Language { Locale.Language(identifier: sourceIsRussian ? "en" : "ru") }

    var body: some View {
        VStack(spacing: 8) {
            languageHeader
            inputRow
            outputRow
        }
        .frame(width: PanelLayout.translatorWidgetWidth, height: PanelLayout.nowPlayingWidgetHeight)
        .translationTask(configuration) { session in
            await performTranslation(using: session)
        }
        .onChange(of: isPanelExpanded) { _, expanded in
            if !expanded { reset() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Russian and English translator")
    }

    private func reset() {
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        configuration = nil
        isTranslating = false
    }

    private var languageHeader: some View {
        HStack(spacing: 8) {
            languageBadge(sourceIsRussian ? "RU" : "EN", isSource: true)

            Button(action: switchLanguages) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 22, height: 18)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Switch languages")

            languageBadge(sourceIsRussian ? "EN" : "RU", isSource: false)
            Spacer()

            Button {
                TranslatorWindowController.shared.show(initialText: sourceText)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Open full translator")
        }
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField(sourceIsRussian ? "Введите текст" : "Enter text", text: $sourceText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .focused($isInputFocused)
                .onSubmit(requestTranslation)

            Button(action: requestTranslation) {
                if isTranslating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(accentColor)
            .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
            .help("Translate")
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    private var outputRow: some View {
        HStack(spacing: 6) {
            Text(errorMessage ?? (translatedText.isEmpty ? "Translation" : translatedText))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(errorMessage == nil ? .white.opacity(translatedText.isEmpty ? 0.35 : 0.75) : .red.opacity(0.8))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !translatedText.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translatedText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Copy translation")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func languageBadge(_ text: String, isSource: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(isSource ? accentColor : .white.opacity(0.5))
    }

    private func switchLanguages() {
        sourceIsRussian.toggle()
        if !translatedText.isEmpty {
            sourceText = translatedText
            translatedText = ""
        }
        errorMessage = nil
        configuration = nil
        isInputFocused = true
    }

    private func requestTranslation() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        errorMessage = nil
        isTranslating = true
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
        } else {
            configuration?.invalidate()
        }
    }

    @MainActor
    private func performTranslation(using session: TranslationSession) async {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            isTranslating = false
            return
        }
        defer { isTranslating = false }

        do {
            let response = try await session.translate(text)
            guard !Task.isCancelled,
                  sourceText.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            translatedText = response.targetText
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Translation unavailable"
        }
    }
}

@MainActor
final class TranslatorWindowController: NSWindowController {
    static let shared = TranslatorWindowController()

    private let model = TranslatorWindowModel()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Translator"
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: TranslatorWindowView(model: model))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(initialText: String) {
        if model.sourceText.isEmpty, !initialText.isEmpty {
            model.sourceText = initialText
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class TranslatorWindowModel: ObservableObject {
    @Published var sourceText = ""
    @Published var translatedText = ""
}

private struct TranslatorWindowView: View {
    @ObservedObject var model: TranslatorWindowModel
    @AppStorage(BangBarSettings.Key.translatorSourceIsRussian) private var sourceIsRussian = true
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var configuration: TranslationSession.Configuration?
    @State private var errorMessage: String?
    @State private var isTranslating = false

    private var accentColor: Color { Color(hex: accentColorHex) }
    private var sourceLanguage: Locale.Language { Locale.Language(identifier: sourceIsRussian ? "ru" : "en") }
    private var targetLanguage: Locale.Language { Locale.Language(identifier: sourceIsRussian ? "en" : "ru") }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 14) {
                editor(
                    title: sourceIsRussian ? "RUSSIAN" : "ENGLISH",
                    text: $model.sourceText,
                    placeholder: sourceIsRussian ? "Введите текст…" : "Enter text…",
                    isEditable: true
                )

                editor(
                    title: sourceIsRussian ? "ENGLISH" : "RUSSIAN",
                    text: $model.translatedText,
                    placeholder: errorMessage ?? "Translation",
                    isEditable: false
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(SettingsTheme.background)
        .containerBackground(SettingsTheme.background, for: .window)
        .environment(\.colorScheme, .dark)
        .translationTask(configuration) { session in
            await performTranslation(using: session)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("> BANGBAR_")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(accentColor)

                Text("TRANSLATOR")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(SettingsTheme.primaryText)
            }

            Spacer()

            HStack(spacing: 10) {
                languagePill(sourceIsRussian ? "RU" : "EN", active: true)

                Button(action: switchLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SettingsTheme.primaryText)
                        .frame(width: 32, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(SettingsTheme.border))
                        )
                }
                .buttonStyle(.plain)
                .help("Switch languages")

                languagePill(sourceIsRussian ? "EN" : "RU", active: false)
            }
        }
        .padding(.leading, 70)
        .padding(.trailing, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SettingsTheme.border).frame(height: 1)
        }
    }

    private func languagePill(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(active ? accentColor : SettingsTheme.secondaryText)
            .frame(width: 34, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(active ? accentColor.opacity(0.13) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(active ? accentColor.opacity(0.55) : SettingsTheme.border)
                    )
            )
    }

    private func editor(
        title: String,
        text: Binding<String>,
        placeholder: String,
        isEditable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SettingsTheme.labelFont)
                .foregroundStyle(SettingsTheme.secondaryText)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(errorMessage == nil ? Color.secondary.opacity(0.55) : Color.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: text)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(SettingsTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .disabled(!isEditable)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isEditable ? accentColor.opacity(0.28) : SettingsTheme.border)
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button {
                model.sourceText = ""
                model.translatedText = ""
                errorMessage = nil
            } label: {
                Label("CLEAR", systemImage: "xmark")
            }
            .buttonStyle(TranslatorOutlineButtonStyle())

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.translatedText, forType: .string)
            } label: {
                Label("COPY", systemImage: "doc.on.doc")
            }
            .buttonStyle(TranslatorOutlineButtonStyle())
            .disabled(model.translatedText.isEmpty)

            Button(action: requestTranslation) {
                if isTranslating {
                    ProgressView().controlSize(.small)
                } else {
                    Label("TRANSLATE", systemImage: "arrow.right")
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(TranslatorPrimaryButtonStyle(accentColor: accentColor))
            .disabled(model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
        }
    }

    private func switchLanguages() {
        sourceIsRussian.toggle()
        if !model.translatedText.isEmpty {
            model.sourceText = model.translatedText
            model.translatedText = ""
        }
        errorMessage = nil
        configuration = nil
    }

    private func requestTranslation() {
        guard !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        isTranslating = true
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
        } else {
            configuration?.invalidate()
        }
    }

    @MainActor
    private func performTranslation(using session: TranslationSession) async {
        let text = model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            isTranslating = false
            return
        }
        defer { isTranslating = false }

        do {
            let response = try await session.translate(text)
            guard !Task.isCancelled,
                  model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            model.translatedText = response.targetText
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Translation unavailable"
        }
    }
}

private struct TranslatorOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(SettingsTheme.primaryText.opacity(configuration.isPressed ? 0.65 : 1))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(SettingsTheme.border))
            )
    }
}

private struct TranslatorPrimaryButtonStyle: ButtonStyle {
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.7 : 0.95))
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(accentColor.opacity(configuration.isPressed ? 0.62 : 0.82))
            )
    }
}
