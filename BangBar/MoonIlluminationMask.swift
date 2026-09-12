import SwiftUI

// Canonical right-lit disk. MoonOrientation alone determines the direction of sunlight.
struct MoonIlluminationMask: Shape {
    let illumination: Double

    func path(in rect: CGRect) -> Path {
        let lit = min(max(illumination, 0), 1)

        if lit <= 0.005 {
            return Path()
        }
        if lit >= 0.9995 {
            return Path(ellipseIn: rect)
        }

        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 36
        let terminatorOffset = CGFloat(1 - 2 * lit) * radius
        var path = Path()

        for step in 0...steps {
            let y = center.y - radius + 2 * radius * CGFloat(step) / CGFloat(steps)
            let x = center.x + circleXOffset(at: y, centerY: center.y, radius: radius)
            let point = CGPoint(x: x, y: y)

            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        for step in stride(from: steps, through: 0, by: -1) {
            let y = center.y - radius + 2 * radius * CGFloat(step) / CGFloat(steps)
            let x = center.x + terminatorOffset * circleXOffset(at: y, centerY: center.y, radius: radius) / radius
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }

    private func circleXOffset(at y: CGFloat, centerY: CGFloat, radius: CGFloat) -> CGFloat {
        let distanceFromCenter = y - centerY
        return sqrt(max(radius * radius - distanceFromCenter * distanceFromCenter, 0))
    }

}
