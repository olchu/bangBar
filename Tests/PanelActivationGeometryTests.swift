import CoreGraphics

@main
struct PanelActivationGeometryTests {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let hidden = CGRect(x: 620, y: 864, width: 200, height: 36)
        let compact = CGRect(x: 560, y: 864, width: 320, height: 36)

        check(rect: hidden, threshold: 0, screen: screen, expected: hidden)
        check(
            rect: hidden,
            threshold: 40,
            screen: screen,
            expected: CGRect(x: 580, y: 824, width: 280, height: 76)
        )
        check(
            rect: hidden,
            threshold: -20,
            screen: screen,
            expected: CGRect(x: 640, y: 884, width: 160, height: 16)
        )
        check(
            rect: compact,
            threshold: 40,
            screen: screen,
            expected: CGRect(x: 520, y: 824, width: 400, height: 76)
        )
        check(
            rect: compact,
            threshold: -20,
            screen: screen,
            expected: CGRect(x: 580, y: 884, width: 280, height: 16)
        )

        precondition(
            PanelActivationGeometry.localTopPinnedBounds(
                size: compact.size,
                threshold: 0
            ) == CGRect(x: 0, y: 0, width: 320, height: 36)
        )
        precondition(
            PanelActivationGeometry.localTopPinnedBounds(
                size: compact.size,
                threshold: 40
            ) == CGRect(x: -40, y: 0, width: 400, height: 76)
        )
        precondition(
            PanelActivationGeometry.localTopPinnedBounds(
                size: compact.size,
                threshold: -20
            ) == CGRect(x: 20, y: 0, width: 280, height: 16)
        )

        let extremeInset = PanelActivationGeometry.zone(
            around: compact,
            threshold: -100,
            screenFrame: screen
        )
        precondition(extremeInset.width >= 1 && extremeInset.height >= 1)
        print("PASS: hidden and compact activation thresholds")
    }

    private static func check(
        rect: CGRect,
        threshold: CGFloat,
        screen: CGRect,
        expected: CGRect
    ) {
        let actual = PanelActivationGeometry.zone(
            around: rect,
            threshold: threshold,
            screenFrame: screen
        )
        precondition(actual == expected, "Expected \(expected), got \(actual)")
    }
}
