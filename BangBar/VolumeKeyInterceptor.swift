import AppKit
import Carbon.HIToolbox
import IOKit.hid

private struct VolumeState {
    var volume: Float
    var isMuted: Bool

    func differs(from other: VolumeState) -> Bool {
        abs(volume - other.volume) > 0.001 || isMuted != other.isMuted
    }
}

/// Takes over the volume keys so the system volume HUD never appears. Swallowing the media key events in an
/// event tap is not enough: macOS 27 changes the volume before any tap sees them. Instead the keys are remapped
/// inside the HID driver (`UserKeyMapping`, the mechanism behind `hidutil`) to F18–F20, which the system has no
/// action for, and a session tap turns those back into volume changes.
final class VolumeKeyInterceptor {
    private enum Action {
        case up, down, mute
    }

    private struct Remapping {
        let source: UInt64
        let destination: UInt64
        let keyCode: Int
        let action: Action
    }

    private static let step: Float = 1 / 16
    private static let fineStep: Float = 1 / 64
    // Consumer-page volume usages (0x0C) to keyboard-page F18–F20 (0x07).
    private static let remappings = [
        Remapping(source: 0xC000000E9, destination: 0x70000006D, keyCode: kVK_F18, action: .up),
        Remapping(source: 0xC000000EA, destination: 0x70000006E, keyCode: kVK_F19, action: .down),
        Remapping(source: 0xC000000E2, destination: 0x70000006F, keyCode: kVK_F20, action: .mute)
    ]
    private static let remappedPairs = remappings.map { (source: $0.source, destination: $0.destination) }
    /// The keys the volume keys arrive as while they are taken over.
    static let remappedKeyCodes = Set(remappings.map(\.keyCode))

    /// A press that changed nothing (up at full volume, down at zero) fires no Core Audio listener, yet the user
    /// still needs the feedback the system HUD would have given.
    var onUnchangedPress: ((_ volume: Float, _ isMuted: Bool) -> Void)?
    private lazy var eventTap: EventTap = {
        let tap = EventTap(name: "volume keys", mask: EventTap.mask([.keyDown, .keyUp])) { [weak self] _, event, _ in
            self?.handle(event) ?? .pass
        }
        // Remapping without a working tap would leave the volume keys doing nothing at all.
        tap.onInstalledChange = { isInstalled in
            HIDKeyRemapping.update(Self.remappedPairs, installed: isInstalled)
        }
        return tap
    }()

    var isEnabled: Bool {
        get { eventTap.isEnabled }
        set { eventTap.isEnabled = newValue }
    }

    /// True only while the keys are really taken over; enabled without Accessibility the system still handles them.
    var isActive: Bool { eventTap.isInstalled }

    init() {
        // Mappings outlive a crash until the next login, so a fresh interceptor starts from none.
        HIDKeyRemapping.update(Self.remappedPairs, installed: false)
    }

    private func handle(_ event: CGEvent) -> EventTapDecision {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let remapping = Self.remappings.first(where: { $0.keyCode == keyCode }) else {
            return .pass
        }
        // Key-downs include auto-repeat, so a held key keeps stepping like the system's volume key.
        if event.type == .keyDown {
            let fine = event.flags.isSuperset(of: [.maskAlternate, .maskShift])
            // Core Audio calls can block (e.g. Bluetooth outputs), and inside the tap callback that stalls all typing.
            DispatchQueue.main.async { [weak self] in
                self?.adjustVolume(remapping.action, fine: fine)
            }
        }
        return .swallow
    }

    private func adjustVolume(_ action: Action, fine: Bool) {
        let device = SystemAudio.defaultOutputDevice
        guard let volume = SystemAudio.volume(of: device) else { return }
        let current = VolumeState(volume: volume, isMuted: SystemAudio.isMuted(device))
        let step = fine ? Self.fineStep : Self.step
        let intended = switch action {
        case .mute: VolumeState(volume: volume, isMuted: !current.isMuted)
        case .up: VolumeState(volume: Self.snapped(volume + step, to: step), isMuted: false)
        case .down: VolumeState(volume: Self.snapped(volume - step, to: step), isMuted: current.isMuted)
        }
        let canApply = (intended.volume == current.volume || SystemAudio.isVolumeSettable(device))
            && (intended.isMuted == current.isMuted || SystemAudio.isMuteSettable(device))
        guard canApply, intended.differs(from: current) else {
            onUnchangedPress?(current.volume, current.isMuted)
            return
        }
        if intended.isMuted != current.isMuted {
            SystemAudio.setMuted(intended.isMuted, of: device)
        }
        if intended.volume != current.volume {
            SystemAudio.setVolume(intended.volume, of: device)
        }
    }

    /// Lands on the step grid, so a volume set elsewhere to 0.3 goes to 0.375, not 0.3625.
    private static func snapped(_ volume: Float, to step: Float) -> Float {
        min(max((volume / step).rounded() * step, 0), 1)
    }
}

/// Edits `UserKeyMapping` on every keyboard and consumer-control service while keeping the user's own entries
/// (e.g. a Caps Lock remap made with `hidutil`).
private enum HIDKeyRemapping {
    private static let propertyKey = "UserKeyMapping" as CFString
    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"

    /// Drops existing copies of `entries`, then adds them back when `installed`. Only exact source/destination
    /// pairs count as ours, so a user's own mapping of the same keys survives.
    static func update(_ entries: [(source: UInt64, destination: UInt64)], installed: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return }
        let ours: [NSDictionary] = entries.map {
            [sourceKey: NSNumber(value: $0.source), destinationKey: NSNumber(value: $0.destination)] as NSDictionary
        }
        for service in services where isKeyboardOrConsumerControl(service) {
            let existing: [NSDictionary]
            if let property = IOHIDServiceClientCopyProperty(service, propertyKey) {
                // Writing over a mapping that cannot be read would wipe the user's entries.
                guard let entries = property as? [NSDictionary] else { continue }
                existing = entries
            } else {
                existing = []
            }
            let updated = existing.filter { !ours.contains($0) } + (installed ? ours : [])
            guard updated != existing else { continue }
            IOHIDServiceClientSetProperty(service, propertyKey, updated as CFArray)
        }
    }

    private static func isKeyboardOrConsumerControl(_ service: IOHIDServiceClient) -> Bool {
        IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0
            || IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_ConsumerControl)) != 0
    }
}
