import AppKit
import SwiftUI

struct DayPlansWidget: View {
    @ObservedObject var service: DayPlanService
    let isPanelContentVisible: Bool

    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var scrollViewIdentity = UUID()
    @State private var pendingScrollReset: Task<Void, Never>?
    @State private var pendingScrollEnable: Task<Void, Never>?
    @State private var isScrollEnabled = false
    @State private var isMonitoringExternalChanges = false
    @State private var selectedGroupFilterID: UUID?

    private var accentColor: Color { Color(hex: accentColorHex) }

    private var displayedTodayItems: [DayPlanItem] {
        let filteredItems: [DayPlanItem]
        if let selectedGroupFilterID {
            filteredItems = service.todaysItems.filter { $0.groupID == selectedGroupFilterID }
        } else {
            filteredItems = service.todaysItems
        }

        return filteredItems.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if service.todaysItems.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    Group {
                        if isScrollEnabled {
                            ScrollView(.vertical, showsIndicators: true) {
                                planRows
                                    .background { ScrollElasticityDisabler() }
                            }
                            .id(scrollViewIdentity)
                            .scrollClipDisabled(false)
                        } else {
                            planRows
                        }
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 16)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(
            width: PanelLayout.dayPlansWidgetWidth,
            height: PanelLayout.nowPlayingWidgetHeight,
            alignment: .topLeading
        )
        .background {
            PanelSwipeExclusionRegion()
        }
        .onAppear {
            service.refreshDay()
            service.reload()
        }
        .onChange(of: isPanelContentVisible, initial: true) { _, isVisible in
            setExternalMonitoringActive(isVisible)
            pendingScrollReset?.cancel()
            pendingScrollEnable?.cancel()

            if isVisible {
                pendingScrollEnable = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, isPanelContentVisible else { return }

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isScrollEnabled = true
                    }
                }
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isScrollEnabled = false
            }

            pendingScrollReset = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, !isPanelContentVisible else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollViewIdentity = UUID()
                }
            }
        }
        .onDisappear {
            pendingScrollReset?.cancel()
            pendingScrollEnable?.cancel()
            setExternalMonitoringActive(false)
        }
    }

    private func setExternalMonitoringActive(_ isActive: Bool) {
        guard isActive != isMonitoringExternalChanges else { return }
        isMonitoringExternalChanges = isActive
        if isActive {
            service.beginExternalStorageMonitoring()
        } else {
            service.endExternalStorageMonitoring()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 14, height: 16)

            if !service.todaysItems.isEmpty {
                Text("\(displayedTodayItems.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .frame(minWidth: 10, alignment: .leading)
            }

            groupFilterDots

            Spacer(minLength: 2)

            Button {
                service.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Sync tasks")

            Button {
                DayPlansWindowController.shared.show()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Open tasks")
        }
    }

    private var planRows: some View {
        VStack(spacing: 1) {
            ForEach(displayedTodayItems) { plan in
                DayPlanRow(
                    plan: plan,
                    group: service.group(for: plan),
                    accentColor: accentColor,
                    isPanelContentVisible: isPanelContentVisible
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        service.togglePlanCompletion(plan)
                    }
                }
            }
        }
        .padding(.top, 1)
    }

    private var groupFilterDots: some View {
        HStack(spacing: 1) {
            ForEach(service.groups.prefix(DayPlanService.maximumGroupCount)) { group in
                Button {
                    selectedGroupFilterID = selectedGroupFilterID == group.id ? nil : group.id
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: group.colorHex))
                            .frame(width: selectedGroupFilterID == group.id ? 8 : 6, height: selectedGroupFilterID == group.id ? 8 : 6)

                        if selectedGroupFilterID == group.id {
                            Circle()
                                .fill(Color.black.opacity(0.92))
                                .frame(width: 4, height: 4)
                        }
                    }
                        .frame(width: 13, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(group.name)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: 74, alignment: .leading)
        .clipped()
        .frame(height: 16)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            Text("No plans today")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DayPlanRow: View {
    let plan: DayPlanItem
    let group: DayPlanGroup?
    let accentColor: Color
    let isPanelContentVisible: Bool
    let action: () -> Void

    private var titleColor: Color {
        plan.isCompleted ? .white.opacity(0.42) : .white.opacity(0.9)
    }

    private var statusColor: Color {
        if plan.isCompleted {
            return .white.opacity(0.58)
        }
        return group.map { Color(hex: $0.colorHex) } ?? accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    if !plan.isCompleted {
                        Circle()
                            .stroke(statusColor.opacity(0.75), lineWidth: 2.5)
                            .frame(width: 15, height: 15)
                            .blur(radius: 2.5)
                    }

                    Circle()
                        .stroke(statusColor, lineWidth: 1.5)
                        .frame(width: 15, height: 15)

                    if plan.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }

                Text(plan.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(titleColor)
                    .strikethrough(plan.isCompleted, color: titleColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 2)
            .padding(.trailing, 2)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(plan.title)
        .accessibilityValue(plan.isCompleted ? "Completed today" : "Not completed")
        .accessibilityHint("Toggles completion")
        .overlay(
            PanelTooltipTrackingView(text: tooltipText, isPanelContentVisible: isPanelContentVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    private var tooltipText: String {
        var lines = [plan.title]
        if let group {
            lines.append(group.name)
        }
        if plan.isCompleted {
            lines.append("Completed")
        }
        return lines.joined(separator: "\n")
    }
}
