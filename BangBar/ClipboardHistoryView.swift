import SwiftUI

private let clipboardPinColor = Color(hex: "#FF9F0A")
private let clipboardCardHeight = PanelLayout.nowPlayingWidgetHeight - 4

enum ClipboardHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case images = "Images"

    var id: Self { self }
}

private enum ClipboardHistoryEntry: Identifiable {
    case group(ClipboardImageGroup)
    case item(ClipboardHistoryItem)

    var id: String {
        switch self {
        case .group(let group): "group-\(group.id)"
        case .item(let item): "item-\(item.id)"
        }
    }

    var isPinned: Bool {
        switch self {
        case .group(let group): group.isPinned
        case .item(let item): item.isPinned
        }
    }

    var createdAt: Date {
        switch self {
        case .group(let group): group.createdAt
        case .item(let item): item.createdAt
        }
    }
}

private enum ClipboardHistoryDisplayEntry: Identifiable {
    case group(ClipboardImageGroup)
    case image(ClipboardHistoryItem)
    case textColumn([ClipboardHistoryItem])

    var id: String {
        switch self {
        case .group(let group): "group-\(group.id)"
        case .image(let item): "image-\(item.id)"
        case .textColumn(let items): "text-column-\(items.first?.id.uuidString ?? "empty")"
        }
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var service: ClipboardHistoryService
    let filter: ClipboardHistoryFilter
    let topSafeInset: CGFloat
    @State private var selectedGroupID: UUID?

    private var selectedGroup: ClipboardImageGroup? {
        guard let selectedGroupID else { return nil }
        return service.groups.first { $0.id == selectedGroupID }
    }

    private var filteredItems: [ClipboardHistoryItem] {
        let items = switch filter {
        case .all:
            service.items.filter { $0.groupID == nil }
        case .text:
            service.items.filter { $0.kind == .text }
        case .images:
            service.items.filter { $0.kind == .image && $0.groupID == nil }
        }
        return service.pinnedFirst(items)
    }

    private var visibleGroups: [ClipboardImageGroup] {
        filter == .text ? [] : service.pinnedFirstGroups.filter { !service.items(in: $0).isEmpty }
    }

    private var historyEntries: [ClipboardHistoryEntry] {
        (visibleGroups.map(ClipboardHistoryEntry.group) + filteredItems.map(ClipboardHistoryEntry.item))
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
    }

    private var displayEntries: [ClipboardHistoryDisplayEntry] {
        var result: [ClipboardHistoryDisplayEntry] = []
        var textBuffer: [ClipboardHistoryItem] = []

        func flushTextBuffer() {
            guard !textBuffer.isEmpty else { return }
            result.append(.textColumn(textBuffer))
            textBuffer.removeAll(keepingCapacity: true)
        }

        for entry in historyEntries {
            switch entry {
            case .group(let group):
                flushTextBuffer()
                result.append(.group(group))
            case .item(let item) where item.kind == .text:
                if let first = textBuffer.first, first.isPinned != item.isPinned {
                    flushTextBuffer()
                }
                textBuffer.append(item)
                if textBuffer.count == 3 {
                    flushTextBuffer()
                }
            case .item(let item):
                flushTextBuffer()
                result.append(.image(item))
            }
        }

        flushTextBuffer()
        return result
    }

    var body: some View {
        Group {
            if let selectedGroup {
                groupDetail(selectedGroup)
            } else if filteredItems.isEmpty && visibleGroups.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(displayEntries) { entry in
                            switch entry {
                            case .group(let group):
                                ClipboardGroupCard(
                                    group: group,
                                    images: Array(service.items(in: group).prefix(3)).compactMap {
                                        service.image(for: $0)
                                    },
                                    itemCount: service.items(in: group).count,
                                    isCollecting: service.activeGroupID == group.id,
                                    onOpen: { selectedGroupID = group.id },
                                    onCopy: { service.copy(group) },
                                    onTogglePin: { service.togglePin(group) },
                                    onRename: { service.rename(group, to: $0) },
                                    onDelete: { service.delete(group) }
                                )
                            case .image(let item):
                                ClipboardHistoryCard(
                                    item: item,
                                    image: service.image(for: item),
                                    onCopy: { service.copy(item) },
                                    onTogglePin: { service.togglePin(item) },
                                    onRemove: { service.remove(item) }
                                )
                            case .textColumn(let items):
                                ClipboardTextColumn(
                                    items: items,
                                    onCopy: service.copy,
                                    onTogglePin: service.togglePin,
                                    onRemove: service.remove
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, PanelLayout.expandedHorizontalPadding)
        .padding(.top, topSafeInset)
        .padding(.bottom, PanelLayout.expandedVisibleEdgePadding)
        .onChange(of: filter) { _, newFilter in
            if newFilter == .text {
                selectedGroupID = nil
            }
        }
        .onChange(of: service.groups) { _, groups in
            if let selectedGroupID, !groups.contains(where: { $0.id == selectedGroupID }) {
                self.selectedGroupID = nil
            }
        }
    }

    private func groupDetail(_ group: ClipboardImageGroup) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                Button {
                    selectedGroupID = nil
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 54, height: clipboardCardHeight)
                    .background(Color.white.opacity(0.035))
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.13))
                    }
                }
                .buttonStyle(ClipboardCardButtonStyle())
                .help("Back to clipboard history")

                ForEach(service.items(in: group)) { item in
                    ClipboardHistoryCard(
                        item: item,
                        image: service.image(for: item),
                        onCopy: { service.copy(item) },
                        onTogglePin: { service.togglePin(item) },
                        onRemove: { service.remove(item) }
                    )
                }
            }
        }
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

private struct ClipboardTextColumn: View {
    let items: [ClipboardHistoryItem]
    let onCopy: (ClipboardHistoryItem) -> Void
    let onTogglePin: (ClipboardHistoryItem) -> Void
    let onRemove: (ClipboardHistoryItem) -> Void

    var body: some View {
        VStack(spacing: 3) {
            ForEach(items) { item in
                ClipboardTextRow(
                    item: item,
                    onCopy: { onCopy(item) },
                    onTogglePin: { onTogglePin(item) },
                    onRemove: { onRemove(item) }
                )
            }

            if items.count < 3 {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 230, height: clipboardCardHeight, alignment: .top)
    }
}

private struct ClipboardTextRow: View {
    let item: ClipboardHistoryItem
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onRemove: () -> Void
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var isHovering = false
    @State private var copyFeedbackID: UUID?

    private var accentColor: Color { Color(hex: accentColorHex) }
    private var didCopy: Bool { copyFeedbackID != nil }

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor.opacity(isHovering ? 1 : 0.72))
                .frame(width: 3, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text ?? "")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedTime(at: context.date))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.78))
                }
            }

            if didCopy {
                Label("COPIED", systemImage: "checkmark")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if item.isPinned || isHovering {
                actions
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: (clipboardCardHeight - 6) / 3)
        .contentShape(.rect)
        .background {
            ZStack {
                if item.isPinned {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(clipboardPinColor.opacity(0.064))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(clipboardPinColor.opacity(0.1), lineWidth: 0.75)
                        }
                        .shadow(color: clipboardPinColor.opacity(0.17), radius: 7)
                }

                if isHovering && !item.isPinned {
                    Color.white.opacity(0.04)
                }

                if didCopy {
                    accentColor.opacity(0.11)
                }
            }
        }
        .onTapGesture(perform: copyWithFeedback)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Copy", action: copyWithFeedback)
            Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Delete", role: .destructive, action: onRemove)
        }
        .help(item.text ?? "Click to copy")
    }

    private func copyWithFeedback() {
        onCopy()
        let feedbackID = UUID()
        withAnimation(.easeOut(duration: 0.12)) {
            copyFeedbackID = feedbackID
        }
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            guard copyFeedbackID == feedbackID else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                copyFeedbackID = nil
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 3) {
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(clipboardPinColor)
            }
            .help(item.isPinned ? "Unpin" : "Pin")

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(accentColor)
                }
                .help("Delete")
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .buttonStyle(.plain)
    }

    private func elapsedTime(at date: Date) -> String {
        let seconds = max(Int(date.timeIntervalSince(item.createdAt)), 0)
        if seconds < 60 { return "\(seconds) sec" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr" }
        return "\(hours / 24) d"
    }
}

private struct ClipboardGroupCard: View {
    let group: ClipboardImageGroup
    let images: [NSImage]
    let itemCount: Int
    let isCollecting: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var editedName = ""

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                thumbnailStack

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        if isCollecting {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 5, height: 5)
                        }
                        Text(group.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }

                    Text("\(itemCount) images")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))

                    Spacer()

                    Button(action: onCopy) {
                        Label("Copy all", systemImage: "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accentColor.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .help("Copy all images as files")
                }
                .padding(.vertical, 11)
            }
            .padding(.horizontal, 11)
            .frame(width: 205, height: clipboardCardHeight, alignment: .leading)
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
            .onTapGesture(perform: onOpen)

            if group.isPinned || isHovering {
                HStack(spacing: 5) {
                    Button(action: onTogglePin) {
                        Image(systemName: group.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(clipboardPinColor.opacity(group.isPinned ? 1 : 0.78))
                            .frame(width: 24, height: 24)
                            .background(Color.black.opacity(0.78))
                            .clipShape(.rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(group.isPinned ? "Unpin group" : "Pin group")

                    if isHovering {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accentColor.opacity(0.95))
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.78))
                                .clipShape(.rect(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .help("Delete group")
                    }
                }
                .padding(7)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Copy All", action: onCopy)
            Button(group.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Rename") {
                editedName = group.name
                isRenaming = true
            }
            Button("Delete Group", role: .destructive, action: onDelete)
        }
        .alert("Rename Group", isPresented: $isRenaming) {
            TextField("Group name", text: $editedName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { onRename(editedName) }
        }
        .help("Open group")
    }

    private var thumbnailStack: some View {
        ZStack {
            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 76)
                    .clipShape(.rect(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.16))
                    }
                    .rotationEffect(.degrees(Double(index - 1) * 4))
                    .offset(x: CGFloat(index - 1) * 4)
            }
        }
        .frame(width: 72, height: 86)
    }
}

private struct ClipboardHistoryCard: View {
    let item: ClipboardHistoryItem
    let image: NSImage?
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onRemove: () -> Void
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var isHovering = false
    @State private var copyFeedbackID: UUID?

    private var accentColor: Color {
        Color(hex: accentColorHex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: copyWithFeedback) {
                cardContent
                .frame(
                    width: item.kind == .image ? 150 : 180,
                    height: clipboardCardHeight
                )
                .background(Color.white.opacity(0.035))
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    metadataOverlay
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isHovering ? accentColor.opacity(0.9) : Color.white.opacity(0.13),
                            lineWidth: isHovering ? 1.5 : 1
                        )
                }
                .overlay {
                    if copyFeedbackID != nil {
                        ZStack {
                            Color.black.opacity(0.58)

                            VStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                Text("COPIED")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(accentColor)
                        }
                        .transition(.opacity)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(ClipboardCardButtonStyle())

            if item.isPinned || isHovering {
                HStack(spacing: 5) {
                    Button(action: onTogglePin) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(clipboardPinColor.opacity(item.isPinned ? 1 : 0.78))
                            .frame(width: 24, height: 24)
                            .background(Color.black.opacity(0.78))
                            .clipShape(.rect(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.white.opacity(0.12))
                            }
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Unpin" : "Pin")

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
                        .help("Delete")
                    }
                }
                .padding(7)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Copy", action: copyWithFeedback)
            Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Delete", role: .destructive, action: onRemove)
        }
        .help("Click to copy")
    }

    private func copyWithFeedback() {
        onCopy()
        let feedbackID = UUID()
        withAnimation(.easeOut(duration: 0.12)) {
            copyFeedbackID = feedbackID
        }
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            guard copyFeedbackID == feedbackID else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                copyFeedbackID = nil
            }
        }
    }

    private func elapsedTime(at date: Date) -> String {
        let seconds = max(Int(date.timeIntervalSince(item.createdAt)), 0)

        if seconds < 60 {
            return "\(seconds) sec"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hr"
        }

        return "\(hours / 24) d"
    }

    private var metadataOverlay: some View {
        ZStack(alignment: .bottom) {
            if item.kind == .image {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedTime(at: context.date))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: item.kind == .text ? "text.alignleft" : "photo")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 9)
            .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34, alignment: .bottom)
        .allowsHitTesting(false)
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
