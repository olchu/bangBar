import AVFoundation
import AppKit
import EventKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(BangBarSettings.Key.showNowPlayingWidget) private var showNowPlayingWidget = true
    @AppStorage(BangBarSettings.Key.showClockWidget) private var showClockWidget = true
    @AppStorage(BangBarSettings.Key.showMirrorWidget) private var showMirrorWidget = true
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @AppStorage(BangBarSettings.Key.tintWalkingMan) private var tintWalkingMan = true

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentColorHex) },
            set: { accentColorHex = $0.hexString }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Form {
                LaunchAtLoginSettingsRow()

                Section("Widgets") {
                    Toggle("Music", isOn: $showNowPlayingWidget)
                    Toggle("Clock & Calendar", isOn: $showClockWidget)
                    Toggle("Mirror", isOn: $showMirrorWidget)
                    HStack {
                        ColorPicker("Accent color", selection: accentColorBinding, supportsOpacity: false)
                        Spacer()
                        Button("Reset") {
                            accentColorHex = BangBarSettings.defaultAccentColorHex
                        }
                        .controlSize(.small)
                        .disabled(accentColorHex == BangBarSettings.defaultAccentColorHex)
                    }
                    Toggle("Tint walking figure", isOn: $tintWalkingMan)
                }

                PrivacySettingsSection()
            }
            .formStyle(.grouped)
        }
        .padding(22)
        .frame(width: 440, height: 470, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BangBar Settings")
                .font(.system(size: 22, weight: .semibold))

            Text("Manage launch behavior, widgets, and system permissions.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct LaunchAtLoginSettingsRow: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        Section("Launch") {
            Toggle("Open BangBar at login", isOn: launchAtLoginBinding)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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
        Section("Permissions") {
            PermissionRow(
                title: "Camera",
                status: cameraStatusText,
                systemImage: "video.fill",
                buttonTitle: cameraButtonTitle,
                action: handleCameraAccess
            )

            PermissionRow(
                title: "Calendar",
                status: calendarStatusText,
                systemImage: "calendar",
                buttonTitle: calendarButtonTitle,
                action: handleCalendarAccess
            )

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
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}
