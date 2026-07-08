import AVFoundation
import AppKit
import EventKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(BangBarSettings.Key.showNowPlayingWidget) private var showNowPlayingWidget = true
    @AppStorage(BangBarSettings.Key.showClockWidget) private var showClockWidget = true
    @AppStorage(BangBarSettings.Key.showMoonWidget) private var showMoonWidget = true
    @AppStorage(BangBarSettings.Key.showMirrorWidget) private var showMirrorWidget = true
    @AppStorage(BangBarSettings.Key.showPomodoroWidget) private var showPomodoroWidget = true
    @AppStorage(BangBarSettings.Key.showRemindersWidget) private var showRemindersWidget = true
    @AppStorage(BangBarSettings.Key.reminderListId) private var reminderListId = ""
    @AppStorage(BangBarSettings.Key.selectedCalendarIds) private var selectedCalendarIdsRaw = ""
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @AppStorage(BangBarSettings.Key.tintWalkingMan) private var tintWalkingMan = true
    @AppStorage(BangBarSettings.Key.widgetOrder) private var widgetOrderRaw = BangBarSettings.defaultWidgetOrderRaw
    @State private var selectedSettingsTab = SettingsTab.widgets
    @State private var widgetOrder = BangBarWidget.allCases
    @State private var draggedWidget: BangBarWidget?

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentColorHex) },
            set: { accentColorHex = $0.hexString }
        )
    }

    var body: some View {
        let accentColor = Color(hex: accentColorHex)

        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                SettingsSidebar(selectedTab: $selectedSettingsTab, accentColor: accentColor)
                    .frame(width: 240)

                Rectangle()
                    .fill(SettingsTheme.border)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                mainContent(accentColor: accentColor)
            }
        }
        .foregroundStyle(SettingsTheme.primaryText)
        .background(SettingsTheme.background)
        .containerBackground(SettingsTheme.background, for: .window)
        .frame(width: 1180, height: 700)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            loadWidgetOrder()
        }
        .onChange(of: widgetOrderRaw) { _, _ in
            loadWidgetOrder()
        }
    }

    private var titleBar: some View {
        Color.clear
            .frame(height: 48)
    }

    @ViewBuilder
    private func mainContent(accentColor: Color) -> some View {
        switch selectedSettingsTab {
        case .widgets:
            singleColumnContent(title: "WIDGETS", accentColor: accentColor) {
                widgetsSection(accentColor: accentColor)
                    .frame(width: 884)
            }
        case .permissions:
            singleColumnContent(title: "PERMISSIONS", accentColor: accentColor) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("LAUNCH")
                        LaunchAtLoginSettingsRow(accentColor: accentColor)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("ACCESS")
                        PrivacySettingsSection()
                    }
                }
                .frame(width: 520)
            }
        case .appearance:
            singleColumnContent(title: "APPEARANCE", accentColor: accentColor) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionLabel("APPEARANCE")
                    appearanceCard(accentColor: accentColor)
                }
                .frame(width: 520)
            }
        case .about:
            singleColumnContent(title: "ABOUT", accentColor: accentColor) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("BangBar")
                            .font(SettingsTheme.sectionTitleFont)
                            .foregroundStyle(SettingsTheme.primaryText)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("The notch takes a strip of your screen and gives nothing back. BangBar puts that space to work.")

                            Text("Move your cursor up to the notch and a small panel drops down: what's playing, your next event, today's reminders, the moon, a focus timer. Take a look, do the thing, get back to work. It hides again the second you move away.")

                            Text("Made by Olchu Studio. It lives in the menu bar and stays out of the way. No dock icon, no account, nothing to sign into.")
                        }
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                        SettingsDivider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Run into a bug, or want a widget that isn't here yet? Send it my way:")
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundStyle(SettingsTheme.secondaryText)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(verbatim: "ochurkin@gmail.com")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accentColor)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                .onTapGesture {
                                    if let url = URL(string: "mailto:ochurkin@gmail.com") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .frame(width: 884)
            }
        }
    }

    private func singleColumnContent<Content: View>(
        title: String,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                sectionHeader(title, accentColor: accentColor)
                content()
            }
            .padding(.top, 26)
            .padding(.leading, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String, accentColor: Color) -> some View {
        HStack(spacing: 12) {
            Text(">")
                .foregroundStyle(accentColor)
                .font(SettingsTheme.sectionTitleFont)

            Text(title)
                .font(SettingsTheme.sectionTitleFont)
                .foregroundStyle(SettingsTheme.primaryText)
        }
    }

    private func widgetsSection(accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable, disable and reorder widgets.")
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)

                Text("Drag and drop to change their position in the bar.")
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
            }

            enabledWidgetsTray(accentColor: accentColor)

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("AVAILABLE WIDGETS")
                widgetsCard(accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("CALENDAR")
                CalendarListPickerCard(selectedCalendarIdsRaw: $selectedCalendarIdsRaw, accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel("REMINDERS")
                SettingsCard {
                    RemindersListPickerRow(selectedListId: $reminderListId, accentColor: accentColor)
                }
            }
        }
    }

    private func enabledWidgetsTray(accentColor: Color) -> some View {
        let enabledWidgets = widgetOrder.filter(isWidgetEnabled)

        return SettingsCard {
            HStack(spacing: 10) {
                ForEach(enabledWidgets) { widget in
                    WidgetChip(widget: widget)
                        .frame(maxWidth: .infinity)
                        .onDrag {
                            draggedWidget = widget
                            return NSItemProvider(object: widget.rawValue as NSString)
                        } preview: {
                            WidgetChip(widget: widget, isDragPreview: true)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: WidgetOrderDropDelegate(
                                targetWidget: widget,
                                widgets: $widgetOrder,
                                draggedWidget: $draggedWidget,
                                persist: persistWidgetOrder
                            )
                        )
                }
            }
            .padding(.vertical, 18)
        }
    }

    private func widgetsCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(widgetOrder.enumerated()), id: \.element) { index, widget in
                    WidgetSettingsRow(
                        widget: widget,
                        isEnabled: toggleBinding(for: widget),
                        accentColor: accentColor
                    )
                    .onDrag {
                        draggedWidget = widget
                        return NSItemProvider(object: widget.rawValue as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: WidgetOrderDropDelegate(
                            targetWidget: widget,
                            widgets: $widgetOrder,
                            draggedWidget: $draggedWidget,
                            persist: persistWidgetOrder
                        )
                    )

                    if index < widgetOrder.count - 1 {
                        SettingsDivider()
                    }
                }
            }
        }
    }

    private func toggleBinding(for widget: BangBarWidget) -> Binding<Bool> {
        switch widget {
        case .nowPlaying:
            return $showNowPlayingWidget
        case .clock:
            return $showClockWidget
        case .moon:
            return $showMoonWidget
        case .pomodoro:
            return $showPomodoroWidget
        case .reminders:
            return $showRemindersWidget
        case .mirror:
            return $showMirrorWidget
        }
    }

    private func isWidgetEnabled(_ widget: BangBarWidget) -> Bool {
        toggleBinding(for: widget).wrappedValue
    }

    private func loadWidgetOrder() {
        widgetOrder = BangBarSettings.widgetOrder(from: widgetOrderRaw)
        persistWidgetOrder()
    }

    private func persistWidgetOrder() {
        let normalizedOrder = BangBarSettings.widgetOrderRaw(from: widgetOrder)
        if widgetOrderRaw != normalizedOrder {
            widgetOrderRaw = normalizedOrder
        }
    }

    private func appearanceCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("Accent color")
                        .font(SettingsTheme.rowFont)

                    Spacer()

                    AccentColorPicker(
                        selection: accentColorBinding,
                        accentColor: accentColor,
                        hexValue: accentColorHex
                    )

                    Button("Reset") {
                        accentColorHex = BangBarSettings.defaultAccentColorHex
                    }
                    .buttonStyle(SettingsOutlineButtonStyle())
                    .disabled(accentColorHex == BangBarSettings.defaultAccentColorHex)
                }
                .frame(height: 52)

                SettingsDivider()
                SettingsToggleRow(title: "Tint walking figure", isOn: $tintWalkingMan, accentColor: accentColor)
            }
        }
    }
}

private enum SettingsTab: CaseIterable, Identifiable {
    case widgets
    case permissions
    case appearance
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .widgets:
            return "WIDGETS"
        case .permissions:
            return "PERMISSIONS"
        case .appearance:
            return "APPEARANCE"
        case .about:
            return "ABOUT"
        }
    }

    var systemImage: String {
        switch self {
        case .widgets:
            return "circle.grid.3x3.fill"
        case .permissions:
            return "checkmark.shield"
        case .appearance:
            return "paintbrush.pointed"
        case .about:
            return "info.circle"
        }
    }
}

private struct LaunchAtLoginSettingsRow: View {
    let accentColor: Color

    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggleRow(title: "Open BangBar at login", isOn: launchAtLoginBinding, accentColor: accentColor)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(accentColor)
                        .padding(.leading, 2)
                        .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                setLaunchAtLoginEnabled(newValue)
            }
        )
    }

    private func setLaunchAtLoginEnabled(_ shouldEnable: Bool) {
        errorMessage = nil

        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            isEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            errorMessage = error.localizedDescription
        }
    }
}

private struct PrivacySettingsSection: View {
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    private let eventStore = EKEventStore()

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                PermissionRow(
                    title: "Camera",
                    status: cameraStatusText,
                    systemImage: "video.fill",
                    buttonTitle: cameraButtonTitle,
                    action: handleCameraAccess
                )

                SettingsDivider()
                    .padding(.vertical, 18)

                PermissionRow(
                    title: "Calendar",
                    status: calendarStatusText,
                    systemImage: "calendar",
                    buttonTitle: calendarButtonTitle,
                    action: handleCalendarAccess
                )

                SettingsDivider()
                    .padding(.vertical, 18)

                PermissionRow(
                    title: "Automation",
                    status: "Required to control Spotify and Music",
                    systemImage: "gearshape.2.fill",
                    buttonTitle: "Open",
                    action: {
                        openPrivacySettings(anchor: "Privacy_Automation")
                    }
                )
            }
            .padding(.vertical, 22)
        }
        .onAppear {
            refreshStatuses()
        }
    }

    private var cameraStatusText: String {
        switch cameraStatus {
        case .authorized:
            return "Allowed"
        case .notDetermined:
            return "Not requested"
        case .denied, .restricted:
            return "Permission required in System Settings"
        @unknown default:
            return "Unknown"
        }
    }

    private var calendarStatusText: String {
        switch calendarStatus {
        case .fullAccess, .authorized:
            return "Allowed"
        case .writeOnly:
            return "Write only"
        case .notDetermined:
            return "Not requested"
        case .denied, .restricted:
            return "Permission required in System Settings"
        @unknown default:
            return "Unknown"
        }
    }

    private var cameraButtonTitle: String {
        cameraStatus == .notDetermined ? "Request" : "Open"
    }

    private var calendarButtonTitle: String {
        calendarStatus == .notDetermined || calendarStatus == .writeOnly ? "Request" : "Open"
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
    }

    private func handleCameraAccess() {
        if cameraStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async {
                    refreshStatuses()
                }
            }
        } else {
            openPrivacySettings(anchor: "Privacy_Camera")
        }
    }

    private func handleCalendarAccess() {
        switch calendarStatus {
        case .notDetermined, .writeOnly:
            eventStore.requestFullAccessToEvents { _, _ in
                DispatchQueue.main.async {
                    refreshStatuses()
                }
            }
        default:
            openPrivacySettings(anchor: "Privacy_Calendars")
        }
    }

    private func openPrivacySettings(anchor: String) {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let status: String
    let systemImage: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SettingsTheme.secondaryText)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)

                Text(status)
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .buttonStyle(SettingsOutlineButtonStyle())
        }
        .frame(minHeight: 74)
        .padding(.horizontal, 18)
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab

    let accentColor: Color

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 46)

            VStack(spacing: 18) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        accentColor: accentColor
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 14) {
                SettingsIllustration()
                    .frame(height: 190)

                OlchuStudioFooter(accentColor: accentColor)
                    .padding(.horizontal, 24)
            }
        }
    }
}

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 28)

                Text(tab.title)
                    .font(SettingsTheme.sidebarFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? accentColor : SettingsTheme.secondaryText)
            .padding(.horizontal, 20)
            .frame(width: 208, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentColor.opacity(0.18) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? accentColor.opacity(0.75) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsIllustration: View {
    var body: some View {
        Image("settingsIllustration")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct OlchuStudioFooter: View {
    let accentColor: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            logo

            Spacer(minLength: 8)

            Text(appVersionLabel)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(SettingsTheme.secondaryText)
                .lineLimit(1)
                .padding(.bottom, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("> OLCHU_")
                .font(.system(size: 8, weight: .light, design: .monospaced))
                .foregroundStyle(SettingsTheme.primaryText)
                .lineLimit(1)

            HStack(alignment: .center, spacing: 3) {
                Text("STUDI")
                    .font(.system(size: 12, weight: .black, design: .default))
                    .foregroundStyle(SettingsTheme.primaryText)
                    .lineLimit(1)
                    .fixedSize()

                logoDot
            }
        }
        .fixedSize()
    }

    private var logoDot: some View {
        Circle()
            .fill(accentColor)
            .frame(width: 17, height: 17)
    }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v\(version ?? "0.0")"
    }
}

private struct WidgetChip: View {
    let widget: BangBarWidget
    var isDragPreview = false

    var body: some View {
        HStack(spacing: 8) {
            dragHandle

            Image(systemName: widget.systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 16)

            Text(widget.settingsTitle)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(SettingsTheme.primaryText)
        .padding(.horizontal, 10)
        .frame(width: isDragPreview ? widget.settingsChipWidth : nil, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDragPreview ? SettingsTheme.background : SettingsTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(SettingsTheme.border, lineWidth: 1)
                )
        )
    }

    private var dragHandle: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 4) {
                    Circle()
                        .fill(SettingsTheme.secondaryText.opacity(0.58))
                        .frame(width: 2.5, height: 2.5)
                    Circle()
                        .fill(SettingsTheme.secondaryText.opacity(0.58))
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
    }
}

private struct WidgetSettingsRow: View {
    let widget: BangBarWidget
    @Binding var isEnabled: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: widget.systemImage)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(SettingsTheme.primaryText)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(widget.settingsTitle)
                    .font(SettingsTheme.rowFont)
                    .foregroundStyle(SettingsTheme.primaryText)

                Text(widget.subtitle)
                    .font(SettingsTheme.captionFont)
                    .foregroundStyle(SettingsTheme.secondaryText)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(SettingsSwitchToggleStyle(accentColor: accentColor))
        }
        .frame(height: 72)
    }
}

private struct WidgetOrderDropDelegate: DropDelegate {
    let targetWidget: BangBarWidget
    @Binding var widgets: [BangBarWidget]
    @Binding var draggedWidget: BangBarWidget?
    let persist: () -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggedWidget,
            draggedWidget != targetWidget,
            let fromIndex = widgets.firstIndex(of: draggedWidget),
            let toIndex = widgets.firstIndex(of: targetWidget)
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            widgets.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
        persist()
    }

    func performDrop(info: DropInfo) -> Bool {
        persist()
        draggedWidget = nil
        return true
    }
}

private extension BangBarWidget {
    var settingsTitle: String {
        switch self {
        case .clock:
            return "Calendar"
        default:
            return title
        }
    }

    var settingsChipWidth: CGFloat {
        let scaledWidth = realPanelWidth * 0.7 + 70
        return max(scaledWidth, minimumReadableChipWidth)
    }

    private var realPanelWidth: CGFloat {
        switch self {
        case .nowPlaying:
            return PanelLayout.nowPlayingWidgetWidth
        case .clock:
            return PanelLayout.clockWidgetWidth
        case .moon:
            return PanelLayout.moonWidgetWidth
        case .pomodoro:
            return PanelLayout.pomodoroWidgetWidth
        case .reminders:
            return PanelLayout.remindersWidgetWidth
        case .mirror:
            return PanelLayout.mirrorWidgetWidth
        }
    }

    private var minimumReadableChipWidth: CGFloat {
        switch self {
        case .nowPlaying:
            return 160
        case .clock:
            return 170
        case .moon:
            return 150
        case .pomodoro:
            return 174
        case .reminders:
            return 178
        case .mirror:
            return 150
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let accentColor: Color

    var body: some View {
        HStack {
            Text(title)
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SettingsSwitchToggleStyle(accentColor: accentColor))
        }
        .frame(height: 52)
    }
}

private struct AccentColorPicker: View {
    @Binding var selection: Color
    let accentColor: Color
    let hexValue: String

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor)
                    .frame(width: 66, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )

                Text(hexValue.uppercased())
                    .font(SettingsTheme.labelFont)
                    .foregroundStyle(SettingsTheme.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(SettingsTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SettingsTheme.border, lineWidth: 1)
                    )
            )

            ColorPanelClickOverlay(selection: $selection)
                .frame(width: 210, height: 40)
        }
        .frame(width: 210, height: 40)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ColorPanelClickOverlay: NSViewRepresentable {
    @Binding var selection: Color

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onClick = {
            context.coordinator.openColorPanel()
        }
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        context.coordinator.selection = $selection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class ClickView: NSView {
        var onClick: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Color>

        init(selection: Binding<Color>) {
            self.selection = selection
        }

        func openColorPanel() {
            let panel = NSColorPanel.shared
            let color = NSColor(selection.wrappedValue).usingColorSpace(.sRGB) ?? NSColor(selection.wrappedValue)
            panel.showsAlpha = false
            panel.color = color
            panel.setTarget(self)
            panel.setAction(#selector(colorChanged(_:)))
            panel.makeKeyAndOrderFront(nil)
        }

        @objc func colorChanged(_ sender: NSColorPanel) {
            let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
            selection.wrappedValue = Color(nsColor: color)
        }
    }
}

private struct SettingsSwitchToggleStyle: ToggleStyle {
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? accentColor : Color.white.opacity(0.07))
                    .overlay(
                        Capsule()
                            .stroke(
                                configuration.isOn ? accentColor.opacity(0.95) : Color.white.opacity(0.28),
                                lineWidth: 1.2
                            )
                    )

                Circle()
                    .fill(SettingsTheme.primaryText)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
            .frame(width: 54, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(SettingsTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SettingsTheme.border, lineWidth: 1)
                    )
            )
    }
}

private struct SettingsSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(SettingsTheme.labelFont)
            .foregroundStyle(SettingsTheme.secondaryText)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsTheme.border)
            .frame(height: 1)
    }
}

private struct DottedDivider: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<120, id: \.self) { _ in
                Circle()
                    .fill(SettingsTheme.secondaryText.opacity(0.5))
                    .frame(width: 1.5, height: 1.5)
            }
        }
        .frame(width: 1)
    }
}

private struct SettingsOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(configuration.isPressed ? SettingsTheme.primaryText.opacity(0.7) : SettingsTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? SettingsTheme.border.opacity(0.45) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(SettingsTheme.border, lineWidth: 1)
                    )
            )
    }
}

private struct RemindersListPickerRow: View {
    @Binding var selectedListId: String
    let accentColor: Color

    @State private var lists: [(id: String, title: String)] = []

    var body: some View {
        HStack {
            Text("List")
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)

            Spacer()

            Menu {
                Button("All Reminders") { selectedListId = "" }
                if !lists.isEmpty {
                    Divider()
                    ForEach(lists, id: \.id) { list in
                        Button(list.title) { selectedListId = list.id }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedTitle)
                        .font(SettingsTheme.captionFont)
                        .foregroundStyle(SettingsTheme.primaryText)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SettingsTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SettingsTheme.border.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(SettingsTheme.border, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .frame(height: 52)
        .onAppear { loadLists() }
    }

    private var selectedTitle: String {
        if selectedListId.isEmpty { return "All Reminders" }
        return lists.first { $0.id == selectedListId }?.title ?? "All Reminders"
    }

    private func loadLists() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else { return }
        let store = EKEventStore()
        lists = store.calendars(for: .reminder).map { (id: $0.calendarIdentifier, title: $0.title) }
    }
}

private struct CalendarListPickerCard: View {
    @Binding var selectedCalendarIdsRaw: String
    let accentColor: Color

    @State private var calendars: [(id: String, title: String, color: NSColor)] = []
    @State private var authorizationStatus = EKEventStore.authorizationStatus(for: .event)

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                if isAuthorized {
                    if calendars.isEmpty {
                        CalendarPickerStatusRow(text: "No calendars available")
                    } else {
                        calendarActionsRow
                        SettingsDivider()

                        ForEach(Array(calendars.enumerated()), id: \.element.id) { index, calendar in
                            calendarRow(calendar)

                            if index < calendars.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                } else {
                    CalendarPickerStatusRow(text: "Allow Calendar access to choose calendars")
                }
            }
        }
        .onAppear { loadCalendars() }
    }

    private var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    private var selectedCalendarIds: [String]? {
        BangBarSettings.selectedCalendarIds(from: selectedCalendarIdsRaw)
    }

    private var calendarActionsRow: some View {
        HStack(spacing: 10) {
            Text("Shown in widget")
                .font(SettingsTheme.captionFont)
                .foregroundStyle(SettingsTheme.secondaryText)

            Spacer()

            Button("All", action: selectAll)
                .buttonStyle(SettingsOutlineButtonStyle())

            Button("None", action: clearAll)
                .buttonStyle(SettingsOutlineButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private func isSelected(_ id: String) -> Bool {
        selectedCalendarIds?.contains(id) ?? true
    }

    private func calendarRow(_ calendar: (id: String, title: String, color: NSColor)) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(nsColor: calendar.color))
                .frame(width: 10, height: 10)

            Text(calendar.title)
                .font(SettingsTheme.rowFont)
                .foregroundStyle(SettingsTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 16)

            Toggle("", isOn: binding(for: calendar.id))
                .labelsHidden()
                .toggleStyle(SettingsSwitchToggleStyle(accentColor: accentColor))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { isSelected(id) },
            set: { isSelected in
                updateSelection(id: id, isSelected: isSelected)
            }
        )
    }

    private func updateSelection(id: String, isSelected: Bool) {
        var selectedIds = Set(selectedCalendarIds ?? calendars.map(\.id))

        if isSelected {
            selectedIds.insert(id)
        } else {
            selectedIds.remove(id)
        }

        let orderedIds = calendars
            .map(\.id)
            .filter { selectedIds.contains($0) }

        selectedCalendarIdsRaw = orderedIds.count == calendars.count
            ? ""
            : BangBarSettings.selectedCalendarIdsRaw(from: orderedIds)
    }

    private func selectAll() {
        selectedCalendarIdsRaw = ""
    }

    private func clearAll() {
        selectedCalendarIdsRaw = BangBarSettings.selectedCalendarIdsRaw(from: [])
    }

    private func loadCalendars() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized else {
            calendars = []
            return
        }

        let store = EKEventStore()
        calendars = store.calendars(for: .event)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { calendar in
                (
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    color: NSColor(cgColor: calendar.cgColor) ?? .white
                )
            }
    }
}

private struct CalendarPickerStatusRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsTheme.captionFont)
            .foregroundStyle(SettingsTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 18)
    }
}

private enum SettingsTheme {
    static let background = Color.black
    static let cardBackground = Color.black.opacity(0.35)
    static let border = Color.white.opacity(0.13)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.52)

    static let titleFont = Font.system(size: 18, weight: .medium, design: .monospaced)
    static let sectionTitleFont = Font.system(size: 20, weight: .medium, design: .monospaced)
    static let sidebarFont = Font.system(size: 17, weight: .semibold, design: .monospaced)
    static let labelFont = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let chipFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let rowFont = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 13, weight: .regular, design: .monospaced)
}
