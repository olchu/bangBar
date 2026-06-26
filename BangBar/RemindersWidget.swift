import AppKit
import SwiftUI

struct RemindersWidget: View {
    @ObservedObject var service: ReminderService

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    private var accentColor: Color { Color(hex: accentColorHex) }
    @State private var addController: NSWindowController?

    private let maxVisible = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
                .padding(.top, 5)

            switch service.authorizationState {
            case .unknown, .requesting:
                accessPrompt(icon: "bell.badge", line1: "Tap to allow", line2: "access")
                    .onTapGesture { service.requestAccessFromUserAction() }
            case .denied:
                accessPrompt(icon: "bell.slash", line1: "Open Settings", line2: "to enable")
                    .onTapGesture { service.requestAccessFromUserAction() }
            case .failed:
                accessPrompt(icon: "exclamationmark.circle", line1: "Unavailable", line2: nil)
            case .authorized:
                if service.items.isEmpty {
                    emptyState
                } else {
                    activeContent
                }
            }
        }
        .frame(
            width: PanelLayout.remindersWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.badge")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))

            if case .authorized = service.authorizationState, !service.items.isEmpty {
                Text("\(service.items.count) active")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            if case .authorized = service.authorizationState {
                Button {
                    if let existing = addController, existing.window?.isVisible == true {
                        existing.window?.makeKeyAndOrderFront(nil)
                    } else {
                        let controller = AddReminderWindowController(service: service)
                        addController = controller
                        controller.showWindow(nil)
                        controller.window?.makeKeyAndOrderFront(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(service.items.prefix(maxVisible)) { item in
                ReminderRow(item: item, accentColor: accentColor) {
                    service.completeReminder(id: item.id)
                }
            }

            if service.items.count > maxVisible {
                Text("+\(service.items.count - maxVisible) more")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            Text("All clear")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accessPrompt(icon: String, line1: String, line2: String?) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            VStack(spacing: 2) {
                Text(line1)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                if let line2 {
                    Text(line2)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let accentColor: Color
    let onComplete: () -> Void

    @State private var completing = false

    private var isToday: Bool {
        guard let date = item.dueDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private var dateLabel: String? {
        guard let date = item.dueDate else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if item.isOverdue {
            let now = Date()
            let f = DateFormatter()
            if cal.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                f.dateFormat = "EEE"
            } else if cal.isDate(date, equalTo: now, toGranularity: .month) {
                f.dateFormat = "d EEE"
            } else {
                f.dateFormat = "d MMM"
            }
            return f.string(from: date).lowercased()
        }
        if cal.isDateInTomorrow(date) { return "tmr" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) ? "EEE" : "d MMM"
        return f.string(from: date).lowercased()
    }

    var body: some View {
        let rowColor: Color = item.isOverdue ? accentColor : .white.opacity(0.82)

        HStack(spacing: 7) {
            Button {
                guard !completing else { return }
                withAnimation(.easeInOut(duration: 0.15)) { completing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onComplete() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(
                            completing ? accentColor : (item.isOverdue ? accentColor : .white.opacity(0.25)),
                            lineWidth: 1.5
                        )
                    if completing {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                }
                .frame(width: 13, height: 13)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 0) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(completing ? .white.opacity(0.3) : rowColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .strikethrough(completing, color: .white.opacity(0.3))

                    Spacer(minLength: 2)

                    if let label = dateLabel {
                        Text(label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(isToday ? .white.opacity(0.4) : rowColor.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .animation(.easeOut(duration: 0.15), value: completing)
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(
            ReminderTooltipTrackingView(text: tooltipText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    private var tooltipText: String {
        var lines = [item.title]
        if let date = item.dueDate {
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: date)
            let hasTime = comps.hour != 0 || comps.minute != 0
            let f = DateFormatter()
            f.dateStyle = .full
            f.timeStyle = hasTime ? .short : .none
            let prefix = item.isOverdue ? "Overdue · " : "Due: "
            lines.append(prefix + f.string(from: date))
        } else if item.isOverdue {
            lines.append("Overdue · no date")
        }
        return lines.joined(separator: "\n")
    }
}

private struct ReminderTooltipTrackingView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> ReminderTooltipTrackingNSView {
        let view = ReminderTooltipTrackingNSView(frame: .zero)
        view.text = text
        return view
    }

    func updateNSView(_ nsView: ReminderTooltipTrackingNSView, context: Context) {
        nsView.text = text
    }
}

private final class ReminderTooltipTrackingNSView: NSView {
    var text = ""
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        showTooltip(for: event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        TooltipManager.shared.hide()
        super.mouseExited(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            TooltipManager.shared.hide()
        }
    }

    private func showTooltip(for event: NSEvent) {
        guard let window else { return }
        let cursorRect = NSRect(origin: event.locationInWindow, size: .zero)
        let cursorPoint = window.convertToScreen(cursorRect).origin
        TooltipManager.shared.show(text: text, near: cursorPoint, offset: CGSize(width: 14, height: 10))
    }
}
