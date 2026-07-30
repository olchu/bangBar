import SwiftUI
import AppKit

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
    @AppStorage(BangBarSettings.Key.clipboardButtonPosition) private var clipboardButtonPositionRaw = ClipboardButtonPosition.nearNotch.rawValue

    private var accentColor: Color {
        Color(hex: accentColorHex)
    }

    private var clipboardButtonPosition: ClipboardButtonPosition {
        ClipboardButtonPosition(rawValue: clipboardButtonPositionRaw) ?? .nearNotch
    }

    var body: some View {
        GeometryReader { geometry in
            let leftZoneWidth = max(
                (geometry.size.width - PanelLayout.notchWidth(on: NSScreen.main)) / 2 - 8,
                20
            )

            ZStack {
                if clipboardButtonPosition == .nearNotch {
                    HStack(spacing: 9) {
                        if showsClipboardHistory {
                            historyControls
                            toolbarDivider
                        }

                        clipboardToggleButton
                    }
                    .frame(width: leftZoneWidth, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 9) {
                        clipboardToggleButton

                        if showsClipboardHistory {
                            toolbarDivider
                            historyControls
                        }
                    }
                    .padding(.leading, PanelLayout.topBarHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Spacer()

                    if showsClipboardHistory {
                        Button(action: onClear) {
                            Label("Clear", systemImage: "trash")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accentColor.opacity(0.9))
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isClearDisabled)
                        .opacity(isClearDisabled ? 0.35 : 1)
                        .transition(.opacity)
                    }

                    topBarButton(systemImage: "gearshape", help: "Settings", action: onOpenSettings)
                }
                .padding(.horizontal, PanelLayout.topBarHorizontalPadding)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.black)
        .contentShape(.rect)
    }

    private var clipboardToggleButton: some View {
        topBarButton(
            systemImage: showsClipboardHistory ? "square.grid.2x2" : "clipboard",
            help: showsClipboardHistory ? "Show widgets" : "Clipboard history",
            isActive: showsClipboardHistory
        ) {
            withAnimation(.easeOut(duration: 0.18)) {
                showsClipboardHistory.toggle()
            }
        }
    }

    private var historyControls: some View {
        HStack(spacing: 9) {
            HStack(spacing: 2) {
                ForEach(ClipboardHistoryFilter.allCases) { itemFilter in
                    filterTab(itemFilter)
                }
            }

            toolbarDivider
            imageGroupControl
        }
        .transition(.opacity.combined(with: .move(edge: clipboardButtonPosition == .nearNotch ? .trailing : .leading)))
    }

    @ViewBuilder
    private var imageGroupControl: some View {
        if let activeGroupName {
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 5, height: 5)

                Text("\(activeGroupName) · \(activeGroupItemCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Button("Stop", action: onStopGroup)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.white.opacity(0.055))
            .clipShape(.rect(cornerRadius: 6))
        } else {
            Button(action: onNewGroup) {
                Label("New Image Group", systemImage: "photo.badge.plus")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.white.opacity(0.055))
                    .clipShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 12)
    }

    private func filterTab(_ itemFilter: ClipboardHistoryFilter) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                clipboardFilter = itemFilter
            }
        } label: {
            VStack(spacing: 0) {
                Text(itemFilter.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
