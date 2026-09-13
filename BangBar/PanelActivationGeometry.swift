import CoreGraphics

enum PanelActivationGeometry {
    static func localTopPinnedBounds(
        size: CGSize,
        threshold: CGFloat
    ) -> CGRect {
        let horizontalInset = min(
            -threshold,
            max((size.width - 1) / 2, 0)
        )

        return CGRect(
            x: horizontalInset,
            y: 0,
            width: max(size.width - horizontalInset * 2, 1),
            height: max(size.height + threshold, 1)
        )
    }

    static func zone(
        around topPinnedRect: CGRect,
        threshold: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        let top = min(topPinnedRect.maxY, screenFrame.maxY)
        let bottom = min(topPinnedRect.minY - threshold, top - 1)
        let horizontalInset = min(
            -threshold,
            max((topPinnedRect.width - 1) / 2, 0)
        )

        return CGRect(
            x: topPinnedRect.minX + horizontalInset,
            y: bottom,
            width: max(topPinnedRect.width - horizontalInset * 2, 1),
            height: top - bottom
        )
    }
}
