import AppKit
import CoreAudio
import IOKit.hidsystem

/// Swallows the volume up / down / mute media keys and applies them itself, so the system volume HUD never appears.
final class VolumeKeyInterceptor {
    private static let step: Float = 1 / 16
    private static let fineStep: Float = 1 / 64
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`: media keys arrive as system-defined events of this subtype.
    private static let auxControlButtonsSubtype: Int16 = 8
    private static let volumeKeys = [NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE]

    /// Checked per key press; when false the key reaches the system unchanged.
    var shouldIntercept: () -> Bool = { true }
    /// A swallowed press that changed nothing (up at full volume, down at zero): no Core Audio listener fires,
    /// yet the user still needs the feedback the system HUD would have given.
    var onUnchangedPress: ((_ volume: Float, _ isMuted: Bool) -> Void)?
    /// A key-up is swallowed only when its key-down was, so the system never sees half a press.
    private var swallowedKeys: Set<Int32> = []
    private lazy var eventTap = EventTap(name: "volume keys", mask: CGEventMask(1) << CGEventMask(NX_SYSDEFINED)) {
        [weak self] type, event, _ in
        self?.handle(type: type, event: event) ?? Unmanaged.passUnretained(event)
    }

    var isEnabled: Bool {
        get { eventTap.isEnabled }
        set {
            eventTap.isEnabled = newValue
            swallowedKeys.removeAll()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        guard type.rawValue == UInt32(NX_SYSDEFINED),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlButtonsSubtype
        else { return passThrough }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF0000) >> 16)
        guard Self.volumeKeys.contains(keyCode) else { return passThrough }
        let isKeyDown = (nsEvent.data1 & 0xFF00) >> 8 == 0xA
        guard isKeyDown else {
            return swallowedKeys.remove(keyCode) == nil ? passThrough : nil
        }

        let device = SystemAudio.defaultOutputDevice
        // Without a settable control the system shows its own "not available" feedback.
        guard shouldIntercept(),
              SystemAudio.isVolumeSettable(device),
              keyCode != NX_KEYTYPE_MUTE || SystemAudio.isMuteSettable(device),
              let volume = SystemAudio.volume(of: device)
        else {
            swallowedKeys.remove(keyCode)
            return passThrough
        }
        swallowedKeys.insert(keyCode)
        let isMuted = SystemAudio.isMuted(device)
        let step = nsEvent.modifierFlags.isSuperset(of: [.option, .shift]) ? Self.fineStep : Self.step
        switch keyCode {
        case NX_KEYTYPE_MUTE:
            SystemAudio.setMuted(!isMuted, of: device)
        case NX_KEYTYPE_SOUND_UP:
            let target = Self.snapped(volume + step, to: step)
            guard isMuted || abs(target - volume) > 0.001 else {
                onUnchangedPress?(volume, isMuted)
                break
            }
            SystemAudio.setMuted(false, of: device)
            SystemAudio.setVolume(target, of: device)
        default:
            let target = Self.snapped(volume - step, to: step)
            guard abs(target - volume) > 0.001 else {
                onUnchangedPress?(volume, isMuted)
                break
            }
            SystemAudio.setVolume(target, of: device)
        }
        return nil
    }

    /// Lands on the step grid, so a volume set elsewhere to 0.3 goes to 0.375, not 0.3625.
    private static func snapped(_ volume: Float, to step: Float) -> Float {
        min(max((volume / step).rounded() * step, 0), 1)
    }
}
