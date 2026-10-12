import AppKit
import SwiftUI

final class CountdownEditorWindowController: NSWindowController {
    init(service: CountdownService) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 270),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = service.countdown == nil ? "New Countdown" : "Edit Countdown"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        super.init(window: window)
        let view = CountdownEditorView(service: service) { [weak window] in window?.close() }
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    required init?(coder: NSCoder) { nil }
}

struct CountdownEditorView: View {
    @ObservedObject var service: CountdownService
    let onDismiss: () -> Void

    @State private var title: String
    @State private var targetDate: Date
    @State private var includesTime: Bool
    @State private var savedMessage: String?
    @FocusState private var titleFocused: Bool

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    private var accentColor: Color { Color(hex: accentColorHex) }

    private let isEditing: Bool

    init(service: CountdownService, onDismiss: @escaping () -> Void) {
        self.service = service
        self.onDismiss = onDismiss
        let existing = service.countdown
        isEditing = existing != nil
        _title = State(initialValue: existing?.title ?? "")
        _targetDate = State(initialValue: existing?.targetDate ?? Self.defaultTargetDate())
        _includesTime = State(initialValue: existing?.includesTime ?? false)
    }

    var body: some View {
        ZStack {
            formContent
            if let savedMessage { successOverlay(savedMessage) }
        }
        .frame(width: 360, height: 270)
        .background(Color.black)
        .onAppear { titleFocused = true }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleField

            Spacer().frame(height: 20)

            dateRows

            Spacer().frame(height: 14)

            statusLine

            Spacer()

            actionButtons
        }
        .padding(20)
        .opacity(savedMessage == nil ? 1 : 0)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("TITLE")

            TextField("Trip to Tokyo", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($titleFocused)
                .onSubmit { if canSave { commit() } }
                .onChange(of: title) { _, newValue in
                    if newValue.count > CountdownService.maximumTitleLength {
                        title = String(newValue.prefix(CountdownService.maximumTitleLength))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    titleFocused ? accentColor.opacity(0.6) : Color.white.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                )
        }
    }

    private var dateRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("DATE")
                Spacer()
                DatePicker("", selection: $targetDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
            }

            HStack {
                fieldLabel("TIME")
                Spacer()
                if includesTime {
                    DatePicker("", selection: $targetDate, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                }
                Toggle("", isOn: $includesTime)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentColor)
            }
            .frame(height: 22)
        }
    }

    private var statusLine: some View {
        let remaining = CountdownFormatter.remaining(
            now: Date(),
            target: targetDate,
            includesTime: includesTime,
            calendar: .autoupdatingCurrent
        )

        return HStack(spacing: 6) {
            Image(systemName: remaining == .done ? "exclamationmark.circle" : "hourglass")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(remaining == .done ? accentColor : .white.opacity(0.38))

            Text(remaining == .done ? "Elapsed · the widget will show done" : "In \(remaining.text)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(remaining == .done ? accentColor : .white.opacity(0.5))
                .monospacedDigit()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if isEditing {
                Button("Delete") { finish(message: "Removed", action: service.delete) }
                    .buttonStyle(ARSecondaryButtonStyle())
            }

            Spacer()

            Button("Cancel") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(ARSecondaryButtonStyle())

            Button(isEditing ? "Save" : "Create") { commit() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canSave)
                .buttonStyle(ARPrimaryButtonStyle(accentColor: accentColor, enabled: canSave))
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.38))
    }

    private func successOverlay(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(accentColor)
            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var canSave: Bool { !CountdownService.normalizedTitle(title).isEmpty }

    private func commit() {
        guard canSave else { return }
        finish(message: isEditing ? "Saved" : "Created") {
            service.save(title: title, targetDate: targetDate, includesTime: includesTime)
        }
    }

    private func finish(message: String, action: () -> Void) {
        guard savedMessage == nil else { return }
        action()
        withAnimation(.easeOut(duration: 0.18)) { savedMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { onDismiss() }
    }

    private static func defaultTargetDate() -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek) ?? nextWeek
    }
}
