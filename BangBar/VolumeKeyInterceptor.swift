import AppKit
import IOKit.hidsystem

private nonisolated struct VolumeState {
    var volume: Float
    var isMuted: Bool

    func differs(from other: VolumeState) -> Bool {
        abs(volume - other.volume) > 0.001 || isMuted != other.isMuted
    }
}

/// Swallows the volume up / down / mute media keys and applies them itself, so the system volume HUD never appears.
final class VolumeKeyInterceptor {
    private nonisolated enum Action {
        case up, down, mute
    }

    private nonisolated static let step: Float = 1 / 16
    private nonisolated static let fineStep: Float = 1 / 64
    /// The tap runs on the main run loop, so Core Audio calls that block (e.g. Bluetooth outputs) would stall all input
    /// there. A serial queue keeps rapid presses in order.
    private let audioQueue = DispatchQueue(label: "BangBar.VolumeKeys", qos: .userInteractive)

    /// A press that changed nothing (up at full volume, down at zero) fires no Core Audio listener, yet the user
    /// still needs the feedback the system HUD would have given.
    var onUnchangedPress: ((_ volume: Float, _ isMuted: Bool) -> Void)?
    // HID level: at the session level the system has already handled the key and shown its HUD.
    private lazy var eventTap = EventTap(
        name: "volume keys",
        location: .cghidEventTap,
        mask: CGEventMask(1) << CGEventMask(NX_SYSDEFINED)
    ) { [weak self] _, event, _ in
        self?.handle(event) ?? .pass
    }

    var isEnabled: Bool {
        get { eventTap.isEnabled }
        set { eventTap.isEnabled = newValue }
    }

    /// True only while the keys are really taken over; enabled without Accessibility the system still handles them.
    var isActive: Bool { eventTap.isInstalled }

    private func handle(_ event: CGEvent) -> EventTapDecision {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS
        else { return .pass }
        let action: Action? = switch Int32((nsEvent.data1 & 0xFFFF0000) >> 16) {
        case NX_KEYTYPE_SOUND_UP: .up
        case NX_KEYTYPE_SOUND_DOWN: .down
        case NX_KEYTYPE_MUTE: .mute
        default: nil
        }
        // Only the key-down acts (auto-repeat included); a lone key-up does nothing in the system.
        guard let action, (nsEvent.data1 & 0xFF00) >> 8 == NX_KEYDOWN else { return .pass }
        let fine = Self.isFineStepHeld(event)
        audioQueue.async { [weak self] in
            guard let unchanged = Self.adjustVolume(action, fine: fine) else { return }
            DispatchQueue.main.async {
                self?.onUnchangedPress?(unchanged.volume, unchanged.isMuted)
            }
        }
        return .swallow
    }

    /// Returns the current state when the press changed nothing, for the caller to report.
    private nonisolated static func adjustVolume(_ action: Action, fine: Bool) -> VolumeState? {
        let device = SystemAudio.defaultOutputDevice
        guard let volume = SystemAudio.volume(of: device) else { return nil }
        let current = VolumeState(volume: volume, isMuted: SystemAudio.isMuted(device))
        let step = fine ? Self.fineStep : Self.step
        let intended = switch action {
        case .mute: VolumeState(volume: volume, isMuted: !current.isMuted)
        case .up: VolumeState(volume: Self.snapped(volume + step, to: step), isMuted: false)
        case .down: VolumeState(volume: Self.snapped(volume - step, to: step), isMuted: current.isMuted)
        }
        let canApply = (intended.volume == current.volume || SystemAudio.isVolumeSettable(device))
            && (intended.isMuted == current.isMuted || SystemAudio.isMuteSettable(device))
        guard canApply, intended.differs(from: current) else { return current }
        if intended.isMuted != current.isMuted {
            SystemAudio.setMuted(intended.isMuted, of: device)
        }
        if intended.volume != current.volume {
            SystemAudio.setVolume(intended.volume, of: device)
        }
        return nil
    }

    /// Media key events do not always carry the modifier flags, so the session's live modifier state counts too.
    private static func isFineStepHeld(_ event: CGEvent) -> Bool {
        let fineStepFlags: CGEventFlags = [.maskAlternate, .maskShift]
        return event.flags.isSuperset(of: fineStepFlags)
            || CGEventSource.flagsState(.combinedSessionState).isSuperset(of: fineStepFlags)
    }

    /// Lands on the step grid, so a volume set elsewhere to 0.3 goes to 0.375, not 0.3625.
    private nonisolated static func snapped(_ volume: Float, to step: Float) -> Float {
        min(max((volume / step).rounded() * step, 0), 1)
    }
}
