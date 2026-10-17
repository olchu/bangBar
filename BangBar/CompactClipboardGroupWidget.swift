import SwiftUI

struct CompactClipboardGroupWidget: View {
    @ObservedObject var service: ClipboardHistoryService
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        GeometryReader { geo in
            let horizontalPadding = PanelLayout.compactHorizontalPadding
            let previewSize = PanelLayout.compactArtworkSize(forHeight: geo.size.height)

            HStack(spacing: 9) {
                previewStack(size: previewSize)

                VStack(alignment: .leading, spacing: 1) {
                    Text("COLLECTING")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(service.activeGroup?.name ?? "Image group")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(service.activeGroupItemCount) images")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))

                    Text("stops in \(formatTime(Double(service.collectionSecondsRemaining)))")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: accentColor.opacity(0.7), radius: 4)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewStack(size: CGFloat) -> some View {
        let images = service.activeGroup.map { group in
            Array(service.items(in: group).prefix(2)).compactMap { service.thumbnail(for: $0) }
        } ?? []

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(accentColor.opacity(0.14))
                .frame(width: size, height: size)

            if images.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
            } else {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size - 4, height: size - 4)
                        .clipShape(.rect(cornerRadius: 5))
                        .rotationEffect(.degrees(index == 0 ? -3 : 3))
                }
            }
        }
        .frame(width: size + 4, height: size)
    }
}
