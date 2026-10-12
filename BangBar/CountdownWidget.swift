import AppKit
import SwiftUI

struct CountdownWidget: View {
    @ObservedObject var service: CountdownService
    let date: Date

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var editorController: NSWindowController?

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let countdown = service.countdown {
                CountdownDetails(countdown: countdown, now: date, accentColor: accentColor)
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
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var isDone: Bool {
        guard let countdown = service.countdown else { return false }
        return CountdownFormatter.isElapsed(
            now: date,
            target: countdown.targetDate,
            includesTime: countdown.includesTime,
            calendar: .autoupdatingCurrent
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: isDone ? "hourglass.bottomhalf.filled" : "hourglass")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(service.countdown == nil ? .white.opacity(0.45) : accentColor)
                .frame(width: 14, height: 16)

            Spacer()

            Button(action: openEditor) {
                Image(systemName: service.countdown == nil ? "plus" : "pencil")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(service.countdown == nil ? "New countdown" : "Edit countdown")
        }
        .frame(height: 16)
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
        .padding(.bottom, 16)
    }

    private var accessibilityText: String {
        guard let countdown = service.countdown else { return "No countdown. Pick a date." }
        let remaining = CountdownFormatter.remaining(
            now: date,
            target: countdown.targetDate,
            includesTime: countdown.includesTime,
            calendar: .autoupdatingCurrent
        )
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
    let now: Date
    let accentColor: Color

    private var remaining: CountdownRemaining {
        CountdownFormatter.remaining(
            now: now,
            target: countdown.targetDate,
            includesTime: countdown.includesTime,
            calendar: .autoupdatingCurrent
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)

            Text(countdown.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            CountdownValueText(remaining: remaining, accentColor: accentColor)

            Text(targetLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, 6)
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
            .font(.system(size: 26, weight: .bold, design: .rounded))
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
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
    }
}
