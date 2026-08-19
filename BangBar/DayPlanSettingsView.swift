import SwiftUI

struct DayPlanSettingsContent: View {
    @ObservedObject var service: DayPlanService
    let accentColor: Color

    @State private var newPlanTitle = ""
    @State private var newPlanDate = Date()
    @FocusState private var isNewPlanFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                VStack(spacing: 0) {
                    addPlanRow

                    if !service.items.isEmpty {
                        SettingsDivider()

                        ForEach(Array(service.items.enumerated()), id: \.element.id) { index, plan in
                            EditablePlanRow(
                                plan: plan,
                                accentColor: accentColor,
                                onSave: { title, date in service.updatePlan(plan, title: title, date: date) },
                                onDelete: { service.deletePlan(plan) }
                            )

                            if index < service.items.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }

            Text("Each plan shows in the widget only on its assigned day.")
                .font(SettingsTheme.captionFont)
                .foregroundStyle(SettingsTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            service.reload()
        }
    }

    private var addPlanRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentColor)

            TextField("New plan", text: $newPlanTitle)
                .textFieldStyle(.plain)
                .font(SettingsTheme.rowFont)
                .focused($isNewPlanFieldFocused)
                .onSubmit(addPlan)

            DatePicker("", selection: $newPlanDate, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(accentColor)

            Button("Add", action: addPlan)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(canAddPlan ? Color.white : SettingsTheme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(canAddPlan ? accentColor : Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var canAddPlan: Bool {
        !newPlanTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addPlan() {
        guard canAddPlan else { return }
        service.addPlan(title: newPlanTitle, date: newPlanDate)
        newPlanTitle = ""
        isNewPlanFieldFocused = true
    }
}

private struct EditablePlanRow: View {
    let plan: DayPlanItem
    let accentColor: Color
    let onSave: (String, Date) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var date: Date

    init(
        plan: DayPlanItem,
        accentColor: Color,
        onSave: @escaping (String, Date) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.plan = plan
        self.accentColor = accentColor
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: plan.title)
        _date = State(initialValue: EditablePlanRow.date(from: plan.date))
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("Plan title", text: $title)
                .textFieldStyle(.plain)
                .font(SettingsTheme.rowFont)
                .onSubmit(commit)
                .onChange(of: plan.title) { _, newValue in
                    if title != newValue { title = newValue }
                }
                .onChange(of: title) { _, newValue in
                    if newValue.count > 120 {
                        title = String(newValue.prefix(120))
                    }
                }

            DatePicker("", selection: $date, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(accentColor)
                .onChange(of: date) { _, _ in commit() }

            Button(action: commit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Save changes")

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Delete plan")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func commit() {
        onSave(title, date)
    }

    private static func date(from dayIdentifier: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter.date(from: dayIdentifier) ?? Date()
    }
}
