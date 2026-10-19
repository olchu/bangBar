import AppKit
import CoreAudio
import IOKit.hidsystem

private struct VolumeState {
    var volume: Float
    var isMuted: Bool

    func differs(from other: VolumeState) -> Bool {
        abs(volume - other.volume) > 0.001 || isMuted != other.isMuted
    }
}

/// Swallows the volume up / down / mute media keys and applies them itself, so the system volume HUD never appears.
final class VolumeKeyInterceptor {
    private static let step: Float = 1 / 16
    private static let fineStep: Float = 1 / 64
    private static let verificationDelay: TimeInterval = 0.15
    private static let volumeKeys = [NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE]

    var shouldIntercept: () -> Bool = { true }
    /// A swallowed press that changed nothing (up at full volume, down at zero): no Core Audio listener fires,
    /// yet the user still needs the feedback the system HUD would have given.
    var onUnchangedPress: ((_ volume: Float, _ isMuted: Bool) -> Void)?
    var onSystemHandledKey: (() -> Void)?
    private var verification: DispatchWorkItem?
    // HID level: the system handles volume keys before a session tap would see them.
    private lazy var eventTap = EventTap(
        name: "volume keys",
        location: .cghidEventTap,
        mask: CGEventMask(1) << CGEventMask(NX_SYSDEFINED)
    ) { [weak self] _, event, _ in
        self?.handle(event) ?? Unmanaged.passUnretained(event)
    }

    var isEnabled: Bool {
        get { eventTap.isEnabled }
        set {
            eventTap.isEnabled = newValue
            verification?.cancel()
        }
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS
        else { return passThrough }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF0000) >> 16)
        guard Self.volumeKeys.contains(keyCode) else { return passThrough }
        // A lone key-up does nothing in the system.
        guard (nsEvent.data1 & 0xFF00) >> 8 == NX_KEYDOWN else { return passThrough }

        let device = SystemAudio.defaultOutputDevice
        // Without a settable control the system shows its own "not available" feedback.
        guard shouldIntercept(),
              SystemAudio.isVolumeSettable(device),
              keyCode != NX_KEYTYPE_MUTE || SystemAudio.isMuteSettable(device),
              let volume = SystemAudio.volume(of: device)
        else {
            // The system applies this press itself; a pending check would take that change for a double step.
            verification?.cancel()
            return passThrough
        }
        let current = VolumeState(volume: volume, isMuted: SystemAudio.isMuted(device))
        let step = Self.isFineStepHeld(event) ? Self.fineStep : Self.step
        let intended = switch keyCode {
        case NX_KEYTYPE_MUTE: VolumeState(volume: volume, isMuted: !current.isMuted)
        case NX_KEYTYPE_SOUND_UP: VolumeState(volume: Self.snapped(volume + step, to: step), isMuted: false)
        default: VolumeState(volume: Self.snapped(volume - step, to: step), isMuted: current.isMuted)
        }
        guard intended.differs(from: current) else {
            onUnchangedPress?(current.volume, current.isMuted)
            return nil
        }
        apply(intended, over: current, to: device)
        let direction: Float = switch keyCode {
        case NX_KEYTYPE_MUTE: 0
        case NX_KEYTYPE_SOUND_UP: 1
        default: -1
        }
        scheduleVerification(of: intended, direction: direction, step: step, on: device)
        return nil
    }

    private func apply(_ state: VolumeState, over current: VolumeState, to device: AudioDeviceID) {
        if current.isMuted != state.isMuted {
            SystemAudio.setMuted(state.isMuted, of: device)
        }
        SystemAudio.setVolume(state.volume, of: device)
    }

    /// On some macOS versions the system handles the key before any event tap, so it changes the volume again on
    /// top of ours and shows its HUD anyway. Checking shortly after each press catches that: the state is put back
    /// to the single step the user asked for and `onSystemHandledKey` turns interception off.
    /// Only a further move in the press direction counts: devices quantize the level they are given (Bluetooth
    /// absolute volume has 128 steps), and a read-back off by that much must not disable interception for good.
    private func scheduleVerification(
        of intended: VolumeState,
        direction: Float,
        step: Float,
        on device: AudioDeviceID
    ) {
        verification?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, SystemAudio.defaultOutputDevice == device,
                  let volume = SystemAudio.volume(of: device) else { return }
            let actual = VolumeState(volume: volume, isMuted: SystemAudio.isMuted(device))
            let overshoot = (actual.volume - intended.volume) * direction
            guard actual.isMuted != intended.isMuted || overshoot > step / 2 else { return }
            apply(intended, over: actual, to: device)
            onSystemHandledKey?()
        }
        verification = check
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.verificationDelay, execute: check)
    }

    /// Media key events do not always carry the modifier flags, so the session's live modifier state counts too.
    private static func isFineStepHeld(_ event: CGEvent) -> Bool {
        let fineStepFlags: CGEventFlags = [.maskAlternate, .maskShift]
        return event.flags.isSuperset(of: fineStepFlags)
            || CGEventSource.flagsState(.combinedSessionState).isSuperset(of: fineStepFlags)
    }

    /// Lands on the step grid, so a volume set elsewhere to 0.3 goes to 0.375, not 0.3625.
    private static func snapped(_ volume: Float, to step: Float) -> Float {
        min(max((volume / step).rounded() * step, 0), 1)
    }
}
