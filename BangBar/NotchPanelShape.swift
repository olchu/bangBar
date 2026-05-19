import SwiftUI

struct NotchPanelShape: Shape {
    var topRadius: CGFloat = PanelLayout.panelTopRadius
    var bottomRadius: CGFloat = 26
    var topEarInset: CGFloat = PanelLayout.panelTopEarInset

    func path(in rect: CGRect) -> Path {
        var p = Path()

        let topRadius = min(topRadius, min(rect.width, rect.height) / 2)
        let bottomRadius = min(bottomRadius, min(rect.width, rect.height) / 2)
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
