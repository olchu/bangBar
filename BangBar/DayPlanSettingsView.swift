import SwiftUI

struct DayPlanSettingsContent: View {
    @ObservedObject var service: DayPlanService
    let accentColor: Color

    @State private var newGroupName = ""
    @State private var newGroupColor = Color.red
    @State private var isMonitoringExternalChanges = false
    @FocusState private var isNewGroupFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                VStack(spacing: 0) {
                    addGroupRow

                    if !service.groups.isEmpty {
                        SettingsDivider()

                        ForEach(Array(service.groups.enumerated()), id: \.element.id) { index, group in
                            EditableDayPlanGroupRow(
                                group: group,
                                accentColor: accentColor,
                                onSave: { name, color in
                                    service.updateGroup(group, name: name, colorHex: color.hexString)
                                },
                                onDelete: { service.deleteGroup(group) }
                            )

                            if index < service.groups.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }

            Text(groupLimitDescription)
                .font(SettingsTheme.captionFont)
                .foregroundStyle(SettingsTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            service.reload()
            guard !isMonitoringExternalChanges else { return }
            isMonitoringExternalChanges = true
            service.beginExternalStorageMonitoring()
        }
        .onDisappear {
            guard isMonitoringExternalChanges else { return }
            isMonitoringExternalChanges = false
            service.endExternalStorageMonitoring()
        }
    }

    private var addGroupRow: some View {
        HStack(spacing: 12) {
            GroupColorPicker(selection: $newGroupColor)

            TextField("New group", text: $newGroupName)
                .textFieldStyle(.plain)
                .font(SettingsTheme.rowFont)
                .focused($isNewGroupFieldFocused)
                .onSubmit(addGroup)

            Button("Add", action: addGroup)
                .buttonStyle(.plain)
                .disabled(!canAddGroup)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(canAddGroup ? Color.white : SettingsTheme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(canAddGroup ? accentColor : Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var canAddGroup: Bool {
        service.groups.count < DayPlanService.maximumGroupCount
            && !newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var groupLimitDescription: String {
        if service.groups.count >= DayPlanService.maximumGroupCount {
            return "Maximum \(DayPlanService.maximumGroupCount) groups reached. All group filters fit in the widget."
        }
        return "Tasks are created and edited from the Tasks window. You can create up to \(DayPlanService.maximumGroupCount) groups so every color filter fits in the widget."
    }

    private func addGroup() {
        guard canAddGroup else { return }
        service.addGroup(name: newGroupName, colorHex: newGroupColor.hexString)
        newGroupName = ""
        isNewGroupFieldFocused = true
    }
}

private struct EditableDayPlanGroupRow: View {
    let group: DayPlanGroup
    let accentColor: Color
    let onSave: (String, Color) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var color: Color

    init(
        group: DayPlanGroup,
        accentColor: Color,
        onSave: @escaping (String, Color) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.group = group
        self.accentColor = accentColor
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: group.name)
        _color = State(initialValue: Color(hex: group.colorHex))
    }

    var body: some View {
        HStack(spacing: 12) {
            GroupColorPicker(selection: $color)
                .onChange(of: color) { _, _ in commit() }

            TextField("Group name", text: $name)
                .textFieldStyle(.plain)
                .font(SettingsTheme.rowFont)
                .onSubmit(commit)
                .onChange(of: name) { _, newValue in
                    if newValue.count > 32 {
                        name = String(newValue.prefix(32))
                    }
                }
                .onChange(of: group.name) { _, newValue in
                    if name != newValue { name = newValue }
                }
                .onChange(of: group.colorHex) { _, newValue in
                    let newColor = Color(hex: newValue)
                    if color.hexString != newColor.hexString {
                        color = newColor
                    }
                }

            Button(action: commit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Save group")

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Delete group")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func commit() {
        onSave(name, color)
    }
}

private struct GroupColorPicker: View {
    @Binding var selection: Color

    var body: some View {
        ColorPicker(selection: $selection, supportsOpacity: false) {
            HStack(spacing: 8) {
                Circle()
                    .fill(selection)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )

                Text("Color")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsTheme.secondaryText)
            }
        }
        .labelsHidden()
        .frame(width: 72)
        .help("Edit group color")
    }
}
