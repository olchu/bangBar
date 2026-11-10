import SwiftUI

struct TerminalSettingsSection: View {
    let accentColor: Color

    @AppStorage(BangBarSettings.Key.terminalSwipeEnabled) private var swipeEnabled = true
    @AppStorage(BangBarSettings.Key.clipboardSwipeNavigationInverted) private var swipeInverted = false
    @AppStorage(BangBarSettings.Key.terminalShortcutKeyCode)
    private var shortcutKeyCode = BangBarSettings.defaultTerminalShortcut.keyCode
    @AppStorage(BangBarSettings.Key.terminalShortcutModifiers)
    private var shortcutModifiers = BangBarSettings.defaultTerminalShortcut.modifiers
    @AppStorage(BangBarSettings.Key.terminalShortcutLabel)
    private var shortcutLabel = BangBarSettings.defaultTerminalShortcut.label

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("OPENING")
                SettingsCard {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            title: swipeInverted ? "Swipe down to open" : "Swipe up to open",
                            subtitle: swipeInverted
                                ? "Swipe down with two fingers over the widgets to open the terminal; up over the top bar to return. Follows the Clipboard swipe inversion."
                                : "Swipe up with two fingers over the widgets to open the terminal; down over the top bar to return.",
                            isOn: $swipeEnabled,
                            accentColor: accentColor
                        )
                        SettingsDivider()
                        shortcutRow
                    }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("CLOSING")
                SettingsCard {
                    Text("Click outside the panel, press the shortcut again, or use the × in the top bar. The shell keeps running while the panel is hidden; Esc stays with the terminal.")
                        .font(SettingsTheme.descriptionFont)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    /// Mirrors `GlobalHotKey`, which refuses shortcuts that would swallow ordinary typing.
    private var shortcutIsRegistrable: Bool {
        shortcutKeyCode < 0
            || !NSEvent.ModifierFlags(rawValue: UInt(max(shortcutModifiers, 0)))
                .intersection([.command, .control, .option]).isEmpty
    }

    private var shortcutRow: some View {
        SettingsShortcutRow(
            title: "Shortcut",
            subtitle: shortcutIsRegistrable
                ? "Opens the panel straight into the terminal from any app. Needs ⌘, ⌃ or ⌥. Esc clears it."
                : "Not active: this shortcut has no ⌘, ⌃ or ⌥. Record another one, or press Esc to clear it.",
            keyCode: $shortcutKeyCode,
            modifiers: $shortcutModifiers,
            label: $shortcutLabel
        )
    }
}
