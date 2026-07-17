import SwiftUI

enum ClipboardHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case images = "Images"

    var id: Self { self }
}

struct ClipboardHistoryView: View {
    @ObservedObject var service: ClipboardHistoryService
    let filter: ClipboardHistoryFilter
    let topSafeInset: CGFloat

    private var filteredItems: [ClipboardHistoryItem] {
        switch filter {
        case .all:
            return service.items
        case .text:
            return service.items.filter { $0.kind == .text }
        case .images:
            return service.items.filter { $0.kind == .image }
        }
    }

    var body: some View {
        Group {
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            ClipboardHistoryCard(
                                item: item,
                                image: service.image(for: item),
                                onCopy: { service.copy(item) },
                                onRemove: { service.remove(item) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, PanelLayout.expandedHorizontalPadding)
        .padding(.top, topSafeInset)
        .padding(.bottom, PanelLayout.expandedVisibleEdgePadding)
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            Image(systemName: filter == .images ? "photo" : "clipboard")
                .font(.system(size: 18, weight: .medium))
            Text(service.items.isEmpty ? "Copied items will appear here" : "No items in this category")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipboardHistoryCard: View {
    let item: ClipboardHistoryItem
    let image: NSImage?
    let onCopy: () -> Void
    let onRemove: () -> Void
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var isHovering = false

    private var accentColor: Color {
        Color(hex: accentColorHex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onCopy) {
                ZStack(alignment: .bottomLeading) {
                    cardContent

                    HStack {
                        Text(item.createdAt, style: .relative)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: item.kind == .text ? "text.alignleft" : "photo")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(9)
                }
                .frame(
                    width: item.kind == .image ? 150 : 180,
                    height: PanelLayout.nowPlayingWidgetHeight
                )
                .background(Color.white.opacity(0.035))
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isHovering ? accentColor.opacity(0.9) : Color.white.opacity(0.13),
                            lineWidth: isHovering ? 1.5 : 1
                        )
                }
                .contentShape(.rect)
            }
            .buttonStyle(ClipboardCardButtonStyle())

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accentColor.opacity(0.95))
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.78))
                        .clipShape(.rect(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(0.12))
                        }
                }
                .buttonStyle(.plain)
                .padding(7)
                .help("Delete")
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onRemove)
        }
        .help("Click to copy")
    }

    @ViewBuilder
    private var cardContent: some View {
        if let text = item.text {
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(9)
                .padding(.bottom, 17)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(Color.black.opacity(0.12))
        }
    }
}

private struct ClipboardCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
