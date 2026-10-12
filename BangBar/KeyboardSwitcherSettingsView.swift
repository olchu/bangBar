import Carbon
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct KeyboardSwitcherSettingsSection: View {
    let accentColor: Color

    @AppStorage(BangBarSettings.Key.keyboardSwitcherEnabled) private var isEnabled = false
    @AppStorage(BangBarSettings.Key.keyboardSwitcherTrigger)
    private var triggerRaw = KeyboardSwitcherTrigger.doubleShift.rawValue
    @AppStorage(BangBarSettings.Key.keyboardSwitcherShortcutKeyCode) private var shortcutKeyCode = -1
    @AppStorage(BangBarSettings.Key.keyboardSwitcherShortcutModifiers) private var shortcutModifiers = 0
    @AppStorage(BangBarSettings.Key.keyboardSwitcherShortcutLabel) private var shortcutLabel = "Not set"
    @State private var isTrusted = AccessibilityAccess.isTrusted
    @State private var layoutNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("LAYOUT SWITCHER")
                manualCard
            }
            if isEnabled {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionLabel("AUTOMATIC")
                    KeyboardAutoSwitchCard(accentColor: accentColor)
                }
            }
        }
        .onAppear {
            isTrusted = AccessibilityAccess.isTrusted
            layoutNames = KeyboardLayouts.enabled().map(\.name)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            isTrusted = AccessibilityAccess.isTrusted
        }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
        )) { _ in
            layoutNames = KeyboardLayouts.enabled().map(\.name)
        }
    }

    private var manualCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Convert wrong layout",
                    subtitle: "Converts the last typed word, or the selected text, to the next keyboard layout and switches to it: ghbdtn → привет.",
                    isOn: enabledBinding,
                    accentColor: accentColor
                )
                if isEnabled {
                    SettingsDivider()
                    triggerRow
                    if triggerRaw == KeyboardSwitcherTrigger.custom.rawValue {
                        SettingsDivider()
                        shortcutRow
                    }
                    SettingsDivider()
                    layoutsRow
                    if !isTrusted {
                        SettingsDivider()
                        PermissionRow(
                            title: "Accessibility",
                            status: "Required to read and retype text",
                            systemImage: "keyboard",
                            buttonTitle: "Request",
                            action: { AccessibilityAccess.requestOrOpen() },
                            secondaryButtonTitle: "Open",
                            secondaryAction: { openPrivacySettings(anchor: "Privacy_Accessibility") }
                        )
                    }
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                isEnabled = newValue
                if newValue && !AccessibilityAccess.isTrusted {
                    AccessibilityAccess.requestOrOpen()
                }
            }
        )
    }

    private var triggerRow: some View {
        HStack(spacing: 16) {
            rowLabel("Trigger", subtitle: "Double Shift: tap Shift twice quickly without typing in between.")
            Spacer()
            Picker("", selection: $triggerRaw) {
                ForEach(KeyboardSwitcherTrigger.allCases) { trigger in
                    Text(trigger.title).tag(trigger.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 160)
            .tint(accentColor)
        }
        .padding(.vertical, 14)
    }

    private var shortcutRow: some View {
        HStack(spacing: 16) {
            rowLabel("Shortcut", subtitle: "Click, then press the shortcut. The focused app will not receive it.")
            Spacer(minLength: 12)
            ShortcutRecorderField(
                keyCode: $shortcutKeyCode,
                modifiers: $shortcutModifiers,
                label: $shortcutLabel
            )
            .frame(width: 142, height: 30)
        }
        .padding(.vertical, 14)
    }

    private var layoutsRow: some View {
        HStack(spacing: 16) {
            rowLabel(
                "Layouts",
                subtitle: layoutNames.count < 2
                    ? "Add a second keyboard layout in System Settings › Keyboard › Text Input."
                    : "Repeat the trigger to cycle through layouts in this order."
            )
            Spacer()
            Text(layoutNames.isEmpty ? "None" : layoutNames.joined(separator: " → "))
                .font(SettingsTheme.descriptionFont)
                .foregroundStyle(layoutNames.count < 2 ? accentColor : SettingsTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    private func rowLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)
            Text(subtitle)
                .font(SettingsTheme.descriptionFont)
                .foregroundStyle(SettingsTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KeyboardAutoSwitchCard: View {
    let accentColor: Color

    @AppStorage(BangBarSettings.Key.keyboardSwitcherAutoEnabled) private var isAutoEnabled = false
    @AppStorage(BangBarSettings.Key.keyboardSwitcherShowsNotice) private var showsNotice = true
    @AppStorage(BangBarSettings.Key.keyboardSwitcherExceptions) private var exceptionsRaw = ""
    @AppStorage(BangBarSettings.Key.keyboardSwitcherExcludedApps)
    private var excludedAppsRaw = BangBarSettings.defaultKeyboardSwitcherExcludedApps

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Switch automatically",
                    subtitle: "Fixes a word typed in the wrong layout when you press Space or Return. Press Backspace right after to undo — the word is remembered and left alone.",
                    isOn: $isAutoEnabled,
                    accentColor: accentColor
                )
                if isAutoEnabled {
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Show at the notch",
                        subtitle: "Briefly shows what was changed, e.g. ghbdtn → привет.",
                        isOn: $showsNotice,
                        accentColor: accentColor
                    )
                    SettingsDivider()
                    rememberedWordsRow
                    SettingsDivider()
                    excludedAppsHeader
                    ForEach(BangBarSettings.lines(excludedAppsRaw), id: \.self) { bundleID in
                        ExcludedAppRow(bundleID: bundleID) { removeExcludedApp(bundleID) }
                    }
                }
            }
        }
    }

    private var rememberedWordsRow: some View {
        let words = BangBarSettings.lines(exceptionsRaw)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Remembered words")
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)
                Text(words.isEmpty ? "Words you undo appear here and are never switched again." : words.joined(separator: ", "))
                    .font(SettingsTheme.descriptionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Clear") { exceptionsRaw = "" }
                .buttonStyle(SettingsOutlineButtonStyle())
                .disabled(words.isEmpty)
        }
        .padding(.vertical, 14)
    }

    private var excludedAppsHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Excluded apps")
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)
                Text("No automatic switching here. Double Shift still works.")
                    .font(SettingsTheme.descriptionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Add App…", action: addExcludedApps)
                .buttonStyle(SettingsOutlineButtonStyle())
        }
        .padding(.vertical, 14)
    }

    private func addExcludedApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        var apps = BangBarSettings.lines(excludedAppsRaw)
        for bundleID in panel.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier }) where !apps.contains(bundleID) {
            apps.append(bundleID)
        }
        excludedAppsRaw = apps.joined(separator: "\n")
    }

    private func removeExcludedApp(_ bundleID: String) {
        excludedAppsRaw = BangBarSettings.lines(excludedAppsRaw)
            .filter { $0 != bundleID }
            .joined(separator: "\n")
    }
}

private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 12) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(url?.deletingPathExtension().lastPathComponent ?? bundleID)
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)
                Text(url == nil ? "\(bundleID) — not installed" : bundleID)
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Remove", action: onRemove)
                .buttonStyle(SettingsOutlineButtonStyle())
        }
        .padding(.vertical, 8)
    }
}
