import AppKit
import ApplicationServices

func openPrivacySettings(anchor: String) {
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

enum AccessibilityAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestOrOpen() {
        guard !isTrusted else {
            openPrivacySettings(anchor: "Privacy_Accessibility")
            return
        }
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
