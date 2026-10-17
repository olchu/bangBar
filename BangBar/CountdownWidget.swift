import AppKit
import SwiftUI

struct CountdownWidget: View {
    @ObservedObject var service: CountdownService
    let date: Date

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var editorController: NSWindowController?

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        let remaining = service.countdown?.remaining(at: date)
        VStack(alignment: .leading, spacing: 0) {
            header(isDone: remaining == .done)

            if let countdown = service.countdown, let remaining {
                CountdownDetails(countdown: countdown, remaining: remaining, accentColor: accentColor)
            } else {
                emptyState
            }
        }
        .frame(
            width: PanelLayout.countdownWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: openEditor)
        .contextMenu {
            Button(service.countdown == nil ? "New Countdown…" : "Edit Countdown…", action: openEditor)
            if service.countdown != nil {
                Button("Remove Countdown", role: .destructive) { service.delete() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(remaining: remaining))
        .accessibilityAddTraits(.isButton)
    }

    private func header(isDone: Bool) -> some View {
        HStack {
            CountdownHeaderIcon(
                systemName: isDone ? "hourglass.bottomhalf.filled" : "hourglass",
                color: service.countdown == nil ? .white.opacity(0.45) : accentColor
            )

            Spacer()

            Button(action: openEditor) {
                CountdownHeaderIcon(
                    systemName: service.countdown == nil ? "plus" : "pencil",
                    color: .white.opacity(0.5)
                )
            }
            .buttonStyle(.plain)
            .help(service.countdown == nil ? "New countdown" : "Edit countdown")
        }
        .frame(height: CountdownHeaderIcon.size)
    }

    private var emptyState: some View {
        VStack(spacing: 3) {
            Text("No countdown")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text("pick a date")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.32))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }

    private func accessibilityText(remaining: CountdownRemaining?) -> String {
        guard let countdown = service.countdown, let remaining else { return "No countdown. Pick a date." }
        return "\(countdown.title), \(remaining.text)"
    }

    private func openEditor() {
        if let existing = editorController, existing.window?.isVisible == true {
            existing.window?.makeKeyAndOrderFront(nil)
        } else {
            let controller = CountdownEditorWindowController(service: service)
            editorController = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct CountdownDetails: View {
    let countdown: Countdown
    let remaining: CountdownRemaining
    let accentColor: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(countdown.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            CountdownValueText(remaining: remaining, accentColor: accentColor)

            Spacer(minLength: 0)

            Text(targetLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var targetLabel: String {
        let day = countdown.targetDate.formatted(.dateTime.day().month(.abbreviated).year())
        guard countdown.includesTime else { return day.uppercased() }
        let time = countdown.targetDate.formatted(.dateTime.hour().minute())
        return "\(day) · \(time)".uppercased()
    }
}

private struct CountdownValueText: View {
    let remaining: CountdownRemaining
    let accentColor: Color

    var body: some View {
        styledText
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .animation(.snappy, value: remaining)
    }

    private var styledText: Text {
        switch remaining {
        case .done:
            return Text("done").foregroundStyle(accentColor)
        case .lessThanMinute:
            return Text("<1\(unit("m"))").foregroundStyle(accentColor)
        case .parts(let parts):
            return parts.enumerated().reduce(Text(verbatim: "")) { text, element in
                let (index, part) = element
                let value = Text(verbatim: "\(part.value)")
                    .foregroundStyle(index == 0 ? accentColor : .white.opacity(0.94))
                let separator = Text(verbatim: index == 0 ? "" : " ")
                return Text("\(text)\(separator)\(value)\(unit(part.unit))")
            }
        }
    }

    private func unit(_ symbol: String) -> Text {
        Text(verbatim: symbol)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
    }
}

private struct CountdownHeaderIcon: View {
    static let size: CGFloat = 16

    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .frame(width: Self.size, height: Self.size)
            .contentShape(Rectangle())
    }
}
