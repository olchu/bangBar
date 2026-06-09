import AppKit
import SwiftUI

final class AddReminderWindowController: NSWindowController {
    init(service: ReminderService) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "New Reminder"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        super.init(window: window)
        // Capture window directly (not weak self) so close() is reliable
        let view = AddReminderView(service: service) { [weak window] in window?.close() }
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    required init?(coder: NSCoder) { nil }
}

struct AddReminderView: View {
    @ObservedObject var service: ReminderService
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var hasDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var justCreated = false
    @FocusState private var titleFocused: Bool

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        ZStack {
            formContent
            if justCreated { successOverlay }
        }
        .frame(width: 340, height: 240)
        .background(Color.black)
        .onAppear { titleFocused = true }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TITLE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))

                TextField("Reminder title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .focused($titleFocused)
                    .onSubmit { if canAdd { commit() } }
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

            Spacer().frame(height: 20)

            HStack {
                Text("DUE DATE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                Spacer()
                Toggle("", isOn: $hasDate)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentColor)
            }

            if hasDate {
                Spacer().frame(height: 12)
                DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(ARSecondaryButtonStyle())

                Spacer()

                Button("Add Reminder") { commit() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!canAdd)
                    .buttonStyle(ARPrimaryButtonStyle(accentColor: accentColor, enabled: canAdd))
            }
        }
        .padding(20)
        .opacity(justCreated ? 0 : 1)
    }

    private var successOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(accentColor)
            Text("Added")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var canAdd: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private func commit() {
        guard !justCreated else { return }
        service.addReminder(title: title.trimmingCharacters(in: .whitespaces), dueDate: hasDate ? dueDate : nil)
        withAnimation(.easeOut(duration: 0.18)) { justCreated = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { onDismiss() }
    }
}

private struct ARPrimaryButtonStyle: ButtonStyle {
    let accentColor: Color
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(enabled ? .white : .white.opacity(0.35))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(enabled ? accentColor.opacity(configuration.isPressed ? 0.7 : 1) : Color.white.opacity(0.07))
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct ARSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.35 : 0.6))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
