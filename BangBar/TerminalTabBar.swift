import SwiftUI

/// The terminal's tabs in the top bar, left of the notch.
struct TerminalTabBar: View {
    @ObservedObject var service: TerminalSessionService
    let accentColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(service.tabs.enumerated()), id: \.element.id) { index, tab in
                    TerminalTabItem(
                        tab: tab,
                        isSelected: tab.id == service.selectedTabID,
                        shortcutNumber: index < 9 ? index + 1 : nil,
                        accentColor: accentColor,
                        onSelect: { service.select(tab.id) },
                        onClose: { service.closeTab(id: tab.id) }
                    )
                }

                PanelTopBarButton(systemImage: "plus", help: "New tab (⌘T)", action: service.newTab)
            }
        }
    }
}

/// Copies the last command's output; shown in the top bar while there is one.
struct TerminalCopyOutputButton: View {
    @ObservedObject var service: TerminalSessionService
    @State private var showsCopied = false

    var body: some View {
        if service.canCopyLastOutput {
            PanelTopBarButton(
                systemImage: showsCopied ? "checkmark" : "doc.on.doc",
                help: "Copy last command output (⇧⌘C)"
            ) {
                guard service.copyLastOutput() else { return }
                showsCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showsCopied = false }
            }
            .transition(.opacity)
        }
    }
}

private struct TerminalTabItem: View {
    let tab: TerminalTab
    let isSelected: Bool
    let shortcutNumber: Int?
    let accentColor: Color
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 4) {
                // The underline spans the title only, not the close button that appears on hover.
                PanelTopBarTabLabel(isSelected: isSelected, accentColor: accentColor) {
                    HStack(spacing: 4) {
                        if tab.runningCommand != nil {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                        }
                        label
                    }
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 12, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .help("Close tab (⌘W)")
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
    }

    private var label: some View {
        // Truncated by character count: the font is monospaced, and two width-capped texts in one row
        // squeeze each other.
        HStack(spacing: 3) {
            Text(Self.middleTruncated(tab.title, limit: 18))
            if let branch = tab.branch {
                Text("(\(Self.middleTruncated(branch, limit: 16)))")
                    .opacity(0.65)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private static func middleTruncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = (limit - 1) / 2
        return text.prefix(head) + "…" + text.suffix(limit - 1 - head)
    }

    /// The running command, then the folder with its branch, then the shortcut.
    private var help: String {
        var folder = tab.path.map { NSString(string: $0).abbreviatingWithTildeInPath } ?? tab.title
        if let branch = tab.branch {
            folder += " (\(branch))"
        }
        if let shortcutNumber {
            folder += " · ⌘\(shortcutNumber)"
        }
        return [tab.runningCommand, folder].compactMap { $0 }.joined(separator: "\n")
    }
}
