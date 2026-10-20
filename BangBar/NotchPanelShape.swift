import SwiftUI

struct NotchPanelShape: Shape {
    var topRadius: CGFloat = PanelLayout.panelTopRadius
    var bottomRadius: CGFloat = 26
    var topEarInset: CGFloat = PanelLayout.panelTopEarInset

    /// How far the vertical sides sit inside a frame of `size`, and the radius of the bottom corners.
    func body(for size: CGSize) -> (sideInset: CGFloat, bottomRadius: CGFloat) {
        let topRadius = min(topRadius, min(size.width, size.height) / 2)
        return (min(topEarInset, size.width / 4) + topRadius, min(bottomRadius, min(size.width, size.height) / 2))
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()

        let topRadius = min(topRadius, min(rect.width, rect.height) / 2)
        let bottomRadius = body(for: rect.size).bottomRadius
        let topEarInset = min(topEarInset, rect.width / 4)
        let minX = rect.minX + topEarInset
        let maxX = rect.maxX - topEarInset

        p.move(to: CGPoint(x: minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: minX + topRadius, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: minX + topRadius, y: rect.maxY - bottomRadius))
        p.addQuadCurve(
            to: CGPoint(x: minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: minX + topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: maxX - topRadius - bottomRadius, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: maxX - topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: maxX - topRadius, y: rect.minY + topRadius))
        p.addQuadCurve(
            to: CGPoint(x: maxX, y: rect.minY),
            control: CGPoint(x: maxX - topRadius, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: minX, y: rect.minY))
        p.closeSubpath()

        return p
    }
}
