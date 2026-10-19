import CoreAudio
import Foundation
import IOKit.ps
import notify

struct LiveActivity {
    let symbol: String
    let title: String
    let detail: String

    static func power(_ battery: BatteryStatus) -> LiveActivity {
        if battery.isOnPowerAdapter {
            // On the adapter the battery may be held at a charge limit, so "Charging" only when it really is.
            let title = battery.isCharged ? "Charged" : battery.isCharging ? "Charging" : "Plugged in"
            return LiveActivity(symbol: "bolt.fill", title: title, detail: "\(battery.level)%")
        }
        return LiveActivity(
            symbol: BatteryStatus.symbolName(level: battery.level, isCharging: false),
            title: "On battery",
            detail: "\(battery.level)%"
        )
    }
}

final class LiveActivityController {
    private let center: NotchNoticeCenter
    private let powerMonitor = PowerSourceMonitor()
    private let audioMonitor = AudioOutputMonitor()

    init(center: NotchNoticeCenter) {
        self.center = center
    }

    func start() {
        powerMonitor.onAdapterChange = { [weak self] battery in
            guard UserDefaults.standard.bool(forKey: BangBarSettings.Key.liveActivityPowerEnabled) else { return }
            self?.center.present(.activity(.power(battery)))
        }
        audioMonitor.onBluetoothOutput = { [weak self] deviceName in
            guard UserDefaults.standard.bool(forKey: BangBarSettings.Key.liveActivityAudioEnabled) else { return }
            self?.center.present(.activity(LiveActivity(symbol: "headphones", title: deviceName, detail: "Connected")))
        }
        powerMonitor.start()
        audioMonitor.start()
    }
}

/// Reports power adapter connects and disconnects; the state at launch is recorded without a report.
final class PowerSourceMonitor {
    var onAdapterChange: ((BatteryStatus) -> Void)?
    private var token: Int32?
    private var isOnPowerAdapter: Bool?

    func start() {
        guard token == nil else { return }
        isOnPowerAdapter = BatteryStatus.current()?.isOnPowerAdapter
        var token: Int32 = 0
        // Posted only when the providing source switches, unlike the run-loop source that fires on every charge tick.
        let status = notify_register_dispatch(kIOPSNotifyPowerSource, &token, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.powerSourceChanged() }
        }
        if status == NOTIFY_STATUS_OK {
            self.token = token
        }
    }

    deinit {
        if let token {
            notify_cancel(token)
        }
    }

    private func powerSourceChanged() {
        guard let battery = BatteryStatus.current() else { return }
        defer { isOnPowerAdapter = battery.isOnPowerAdapter }
        guard let previous = isOnPowerAdapter, previous != battery.isOnPowerAdapter else { return }
        onAdapterChange?(battery)
    }
}

/// Reports when the default output switches to a Bluetooth device. Reads only Core Audio, so it needs no
/// Bluetooth permission.
final class AudioOutputMonitor {
    var onBluetoothOutput: ((String) -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
    private var currentDevice = AudioDeviceID(kAudioObjectUnknown)
    private var defaultOutputAddress = address(kAudioHardwarePropertyDefaultOutputDevice)

    func start() {
        guard listener == nil else { return }
        currentDevice = Self.defaultOutputDevice()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultOutputChanged() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, listener
        )
        if status == noErr {
            self.listener = listener
        }
    }

    deinit {
        if let listener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, listener
            )
        }
    }

    private func defaultOutputChanged() {
        let device = Self.defaultOutputDevice()
        guard device != currentDevice else { return }
        currentDevice = device
        let transport = Self.uint32Property(kAudioDevicePropertyTransportType, of: device)
        guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
              let name = Self.nameProperty(of: device)
        else { return }
        onBluetoothOutput?(name)
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        uint32Property(kAudioHardwarePropertyDefaultOutputDevice, of: AudioObjectID(kAudioObjectSystemObject))
            ?? AudioDeviceID(kAudioObjectUnknown)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func uint32Property(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func nameProperty(of object: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}
