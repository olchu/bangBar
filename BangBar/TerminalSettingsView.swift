import AppKit
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
    @AppStorage(BangBarSettings.Key.terminalStartingDirectory)
    private var startingDirectory = BangBarSettings.defaultTerminalStartingDirectory
    @AppStorage(BangBarSettings.Key.terminalMaxLines) private var maxLines = PanelLayout.terminalDefaultMaxLines
    @AppStorage(BangBarSettings.Key.terminalWidth) private var width = PanelLayout.terminalDefaultWidth

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
                SettingsSectionLabel("TABS")
                SettingsCard {
                    startingDirectoryRow
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("SIZE")
                SettingsCard {
                    VStack(spacing: 0) {
                        widthRow
                        SettingsDivider()
                        maxHeightRow
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

    private var startingDirectoryRow: some View {
        HStack(spacing: 16) {
            SettingsRowLabel(title: "Default folder", subtitle: "Every new tab starts here. ⌘T opens a tab; ⌘W closes it.")
            Text(startingDirectory)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SettingsTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 260, alignment: .trailing)
            if startingDirectory != BangBarSettings.defaultTerminalStartingDirectory {
                Button("Reset") { startingDirectory = BangBarSettings.defaultTerminalStartingDirectory }
                    .buttonStyle(SettingsOutlineButtonStyle())
            }
            Button("Choose…", action: chooseStartingDirectory)
                .buttonStyle(SettingsOutlineButtonStyle())
        }
        .padding(.vertical, 14)
    }

    private var widthRow: some View {
        let screen = NSScreen.main
        let range = Double(PanelLayout.expandedWidth(forPage: 0, on: screen))...Double(PanelLayout.maximumExpandedWidth(on: screen))
        let canResize = range.upperBound - range.lowerBound >= 20
        let shownWidth = min(max(Double(width), range.lowerBound), range.upperBound)
        return HStack(spacing: 16) {
            SettingsRowLabel(
                title: "Width",
                subtitle: canResize
                    ? "From the width of the first widget page up to the width of the screen."
                    : "The first widget page already fills the screen width."
            )
            // Rounded here rather than with `step:`, which draws a tick for every 10 pt.
            Slider(
                value: Binding(get: { shownWidth }, set: { newValue in
                    // Every drag event lands here; writing only real changes spares the app-wide defaults observers.
                    let rounded = Int((newValue / 10).rounded()) * 10
                    if rounded != width { width = rounded }
                }),
                in: canResize ? range : range.lowerBound...(range.lowerBound + 1)
            )
            .frame(width: 200)
            .tint(accentColor)
            .disabled(!canResize)
            Text(String(Int(shownWidth)) + " pt")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettingsTheme.primaryText)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }

    private var maxHeightRow: some View {
        SettingsPickerRow(
            title: "Maximum height",
            subtitle: "A new tab opens one line tall and grows with its output up to this height, then scrolls.",
            selection: $maxLines,
            values: PanelLayout.terminalMaxLinesOptions,
            label: { $0 == 1 ? "1 line" : "\($0) lines" },
            accentColor: accentColor
        )
    }

    private func chooseStartingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: NSString(string: startingDirectory).expandingTildeInPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startingDirectory = NSString(string: url.path).abbreviatingWithTildeInPath
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
