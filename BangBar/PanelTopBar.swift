import SwiftUI

struct PanelTopBar: View {
    @Binding var showsClipboardHistory: Bool
    @Binding var clipboardFilter: ClipboardHistoryFilter
    let height: CGFloat
    let isClearDisabled: Bool
    let activeGroupName: String?
    let activeGroupItemCount: Int
    let onNewGroup: () -> Void
    let onStopGroup: () -> Void
    let onClear: () -> Void
    let onOpenSettings: () -> Void
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    private var accentColor: Color {
        Color(hex: accentColorHex)
    }

    var body: some View {
        HStack(spacing: 10) {
            topBarButton(
                systemImage: showsClipboardHistory ? "square.grid.2x2" : "clipboard",
                help: showsClipboardHistory ? "Show widgets" : "Clipboard history",
                isActive: showsClipboardHistory
            ) {
                withAnimation(.easeOut(duration: 0.18)) {
                    showsClipboardHistory.toggle()
                }
            }

            if showsClipboardHistory {
                HStack(spacing: 2) {
                    ForEach(ClipboardHistoryFilter.allCases) { itemFilter in
                        filterTab(itemFilter)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))

                if let activeGroupName {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 5, height: 5)

                        Text("\(activeGroupName) · \(activeGroupItemCount)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)

                        Button("Stop", action: onStopGroup)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accentColor)
                            .buttonStyle(.plain)
                    }
                } else {
                    Button(action: onNewGroup) {
                        Label("New Image Group", systemImage: "photo.badge.plus")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if showsClipboardHistory {
                Button(action: onClear) {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accentColor.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(isClearDisabled)
                .opacity(isClearDisabled ? 0.35 : 1)
                .transition(.opacity)
            }

            topBarButton(systemImage: "gearshape", help: "Settings", action: onOpenSettings)
        }
        .padding(.horizontal, PanelLayout.topBarHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.black)
        .contentShape(.rect)
    }

    private func filterTab(_ itemFilter: ClipboardHistoryFilter) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                clipboardFilter = itemFilter
            }
        } label: {
            VStack(spacing: 0) {
                Text(itemFilter.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(clipboardFilter == itemFilter ? accentColor : Color.white.opacity(0.5))
                    .frame(height: 18)

                Rectangle()
                    .fill(clipboardFilter == itemFilter ? accentColor : Color.clear)
                    .frame(height: 2)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func topBarButton(
        systemImage: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isActive ? 0.92 : 0.56))
                .frame(width: 20, height: 20)
                .background(isActive ? Color.white.opacity(0.08) : Color.clear)
                .clipShape(.rect(cornerRadius: 6))
        }
        .help(help)
        .buttonStyle(PanelTopBarButtonStyle())
    }
}

private struct PanelTopBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.58 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
