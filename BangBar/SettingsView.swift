import AVFoundation
import AppKit
import EventKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(BangBarSettings.Key.showNowPlayingWidget) private var showNowPlayingWidget = true
    @AppStorage(BangBarSettings.Key.showClockWidget) private var showClockWidget = true
    @AppStorage(BangBarSettings.Key.showMoonWidget) private var showMoonWidget = true
    @AppStorage(BangBarSettings.Key.showMirrorWidget) private var showMirrorWidget = true
    @AppStorage(BangBarSettings.Key.showPomodoroWidget) private var showPomodoroWidget = true
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @AppStorage(BangBarSettings.Key.tintWalkingMan) private var tintWalkingMan = true
    @State private var selectedSettingsTab = SettingsTab.widgets

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

            Divider()
                .background(SettingsTheme.border)

            HStack(spacing: 0) {
                SettingsSidebar(selectedTab: $selectedSettingsTab, accentColor: accentColor)
                    .frame(width: 300)

                Divider()
                    .background(SettingsTheme.border)

                mainContent(accentColor: accentColor)
            }
        }
        .foregroundStyle(SettingsTheme.primaryText)
        .background(SettingsTheme.background)
        .containerBackground(SettingsTheme.background, for: .window)
        .frame(width: 1180, height: 700)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 118)

            Text("BangBar Settings")
                .font(SettingsTheme.titleFont)
                .foregroundStyle(SettingsTheme.primaryText)

            Spacer()
        }
        .frame(height: 58)
    }

    @ViewBuilder
    private func mainContent(accentColor: Color) -> some View {
        switch selectedSettingsTab {
        case .widgets:
            singleColumnContent(title: "WIDGETS", accentColor: accentColor) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionLabel("WIDGETS")
                    widgetsCard(accentColor: accentColor)
                }
                .frame(width: 520)
            }
        case .permissions:
            singleColumnContent(title: "PERMISSIONS", accentColor: accentColor) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionLabel("LAUNCH")
                        LaunchAtLoginSettingsRow(accentColor: accentColor)
                    }
                    .frame(width: 520)

                    PrivacySettingsSection()
                        .frame(width: 360)
                        .padding(.top, -38)
                }
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BangBar")
                            .font(SettingsTheme.sectionTitleFont)

                        Text("Compact widgets and quick controls around the notch.")
                            .font(SettingsTheme.rowFont)
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }
                    .padding(.vertical, 18)
                }
                .frame(width: 520)
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
            .padding(.top, 38)
            .padding(.leading, 42)
            .padding(.bottom, 40)
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

    private func widgetsCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                SettingsToggleRow(title: "Music", isOn: $showNowPlayingWidget, accentColor: accentColor)
                SettingsDivider()
                SettingsToggleRow(title: "Clock & Calendar", isOn: $showClockWidget, accentColor: accentColor)
                SettingsDivider()
                SettingsToggleRow(title: "Moon", isOn: $showMoonWidget, accentColor: accentColor)
                SettingsDivider()
                SettingsToggleRow(title: "Pomodoro", isOn: $showPomodoroWidget, accentColor: accentColor)
                SettingsDivider()
                SettingsToggleRow(title: "Mirror", isOn: $showMirrorWidget, accentColor: accentColor)
            }
        }
    }

    private func appearanceCard(accentColor: Color) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("Accent color")
                        .font(SettingsTheme.rowFont)

                    Spacer()

                    ColorPicker("", selection: accentColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 86, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(accentColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(SettingsTheme.border, lineWidth: 1)
                                )
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
        VStack(alignment: .leading, spacing: 26) {
            Text("PERMISSIONS")
                .font(SettingsTheme.sectionTitleFont)
                .foregroundStyle(SettingsTheme.primaryText)

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
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 38)
        .padding(.bottom, 40)
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
            Spacer(minLength: 70)

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

            SettingsIllustrationPlaceholder(accentColor: accentColor)
                .padding(.horizontal, 24)

            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                Text("BASED IN DIGITAL SPACE\nWORKING WORLDWIDE")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .lineSpacing(5)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 34)
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
            HStack(spacing: 22) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 30)

                Text(tab.title)
                    .font(SettingsTheme.sidebarFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? accentColor : SettingsTheme.secondaryText)
            .padding(.horizontal, 28)
            .frame(width: 260, height: 58)
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

private struct SettingsIllustrationPlaceholder: View {
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            dotGrid

            Image(systemName: "figure.walk")
                .font(.system(size: 92, weight: .light))
                .foregroundStyle(SettingsTheme.primaryText)
                .offset(x: 22, y: -6)

            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(SettingsTheme.primaryText)
                .offset(x: 158, y: -150)

            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SettingsTheme.primaryText)
                .offset(x: 132, y: -110)

            Circle()
                .fill(accentColor)
                .frame(width: 58, height: 58)
                .overlay(
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { _ in
                            Rectangle()
                                .fill(SettingsTheme.background)
                                .frame(height: 2)
                        }
                    }
                    .padding(.horizontal, 10)
                )
                .offset(x: 174, y: -72)
        }
        .frame(height: 260)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsTheme.secondaryText.opacity(0.6))
                .frame(height: 1)
        }
    }

    private var dotGrid: some View {
        VStack(spacing: 9) {
            ForEach(0..<13, id: \.self) { _ in
                HStack(spacing: 9) {
                    ForEach(0..<13, id: \.self) { _ in
                        Circle()
                            .fill(SettingsTheme.secondaryText.opacity(0.35))
                            .frame(width: 1.5, height: 1.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.bottom, 26)
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
                .toggleStyle(.switch)
                .tint(accentColor)
        }
        .frame(height: 52)
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
    static let rowFont = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 13, weight: .regular, design: .monospaced)
}
