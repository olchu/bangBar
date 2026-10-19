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
    private let volumeKeys = VolumeKeyInterceptor()
    private var settingsObservations: [NSKeyValueObservation] = []

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
        audioMonitor.onVolumeChange = { [weak self] volume, isMuted in
            guard let self, UserDefaults.standard.bool(forKey: BangBarSettings.Key.liveActivityVolumeEnabled) else { return }
            // With the keys taken over this is the only volume feedback, so it shows even over the expanded panel.
            center.present(.volume(level: volume, isMuted: isMuted), overridesSuppression: volumeKeys.isActive)
        }
        volumeKeys.onUnchangedPress = { [weak self] volume, isMuted in
            self?.audioMonitor.onVolumeChange?(volume, isMuted)
        }
        powerMonitor.start()
        audioMonitor.start()

        // KVO on just these two keys: UserDefaults.didChangeNotification fires for every write in the app.
        settingsObservations = [\UserDefaults.liveActivityVolumeEnabled, \UserDefaults.volumeHUDReplacesSystem].map {
            UserDefaults.standard.observe($0) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateVolumeKeys() }
            }
        }
        updateVolumeKeys()
    }

    private func updateVolumeKeys() {
        let defaults = UserDefaults.standard
        volumeKeys.isEnabled = defaults.bool(forKey: BangBarSettings.Key.liveActivityVolumeEnabled)
            && defaults.bool(forKey: BangBarSettings.Key.volumeHUDReplacesSystem)
    }

    /// Gives the volume keys back to the system.
    func stop() {
        settingsObservations.removeAll()
        volumeKeys.isEnabled = false
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

/// Reports default output switches to a Bluetooth device and volume or mute changes on the default output.
/// Reads only Core Audio, so it needs no Bluetooth permission.
final class AudioOutputMonitor {
    var onBluetoothOutput: ((String) -> Void)?
    var onVolumeChange: ((_ volume: Float, _ isMuted: Bool) -> Void)?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var currentDevice = AudioDeviceID(kAudioObjectUnknown)
    private var lastVolume: (volume: Float, isMuted: Bool)?
    /// Bluetooth devices push a volume sync right after becoming the default output; that is not a user change
    /// and would replace the "Connected" notice.
    private var ignoresVolumeUntil = Date.distantPast
    private static let deviceSwitchVolumeGrace: TimeInterval = 1
    private var defaultOutputAddress = SystemAudio.address(kAudioHardwarePropertyDefaultOutputDevice)

    func start() {
        guard deviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultOutputChanged() }
        }
        guard AudioObjectAddPropertyListenerBlock(SystemAudio.systemObject, &defaultOutputAddress, .main, listener) == noErr
        else { return }
        deviceListener = listener
        attachVolumeListeners(to: SystemAudio.defaultOutputDevice)
    }

    deinit {
        if let deviceListener {
            AudioObjectRemovePropertyListenerBlock(SystemAudio.systemObject, &defaultOutputAddress, .main, deviceListener)
        }
        detachVolumeListeners()
    }

    private func defaultOutputChanged() {
        let device = SystemAudio.defaultOutputDevice
        guard device != currentDevice else { return }
        attachVolumeListeners(to: device)
        ignoresVolumeUntil = Date().addingTimeInterval(Self.deviceSwitchVolumeGrace)
        guard SystemAudio.isBluetooth(device), let name = SystemAudio.name(of: device) else { return }
        onBluetoothOutput?(name)
    }

    /// Moves the volume and mute listeners to `device`; its current level is recorded without a report.
    private func attachVolumeListeners(to device: AudioDeviceID) {
        detachVolumeListeners()
        currentDevice = device
        lastVolume = SystemAudio.volume(of: device).map { ($0, SystemAudio.isMuted(device)) }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeChanged() }
        }
        var volumeAddress = SystemAudio.volumeAddress
        var muteAddress = SystemAudio.muteAddress
        let volumeStatus = AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, listener)
        let muteStatus = AudioObjectAddPropertyListenerBlock(device, &muteAddress, .main, listener)
        if volumeStatus == noErr || muteStatus == noErr {
            volumeListener = listener
        }
    }

    private func detachVolumeListeners() {
        guard let volumeListener else { return }
        var volumeAddress = SystemAudio.volumeAddress
        var muteAddress = SystemAudio.muteAddress
        AudioObjectRemovePropertyListenerBlock(currentDevice, &volumeAddress, .main, volumeListener)
        AudioObjectRemovePropertyListenerBlock(currentDevice, &muteAddress, .main, volumeListener)
        self.volumeListener = nil
    }

    private func volumeChanged() {
        guard let volume = SystemAudio.volume(of: currentDevice) else { return }
        let isMuted = SystemAudio.isMuted(currentDevice)
        // Volume and mute listeners both fire for one key press on some devices.
        guard lastVolume.map({ $0.volume != volume || $0.isMuted != isMuted }) ?? true else { return }
        lastVolume = (volume, isMuted)
        guard Date() >= ignoresVolumeUntil else { return }
        onVolumeChange?(volume, isMuted)
    }
}
