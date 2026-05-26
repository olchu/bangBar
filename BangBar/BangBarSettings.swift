import Foundation
import SwiftUI

enum BangBarSettings {
    enum Key {
        static let showNowPlayingWidget = "showNowPlayingWidget"
        static let showClockWidget = "showClockWidget"
        static let showMirrorWidget = "showMirrorWidget"
        static let accentColorHex = "accentColorHex"
        static let tintWalkingMan = "tintWalkingMan"
    }

    static let defaultAccentColorHex = "#FF383C"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showNowPlayingWidget: true,
            Key.showClockWidget: true,
            Key.showMirrorWidget: true,
            Key.accentColorHex: defaultAccentColorHex,
            Key.tintWalkingMan: true
        ])
    }

    static var showNowPlayingWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showNowPlayingWidget) as? Bool ?? true
    }

    static var showClockWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showClockWidget) as? Bool ?? true
    }

    static var showMirrorWidget: Bool {
        UserDefaults.standard.object(forKey: Key.showMirrorWidget) as? Bool ?? true
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}

