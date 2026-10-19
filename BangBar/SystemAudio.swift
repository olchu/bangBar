import AudioToolbox
import CoreAudio

nonisolated enum SystemAudio {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static var defaultOutputDevice: AudioDeviceID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        return uint32(at: &address, of: systemObject) ?? AudioDeviceID(kAudioObjectUnknown)
    }

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyTransportType)
        let transport = uint32(at: &address, of: device)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    static func name(of device: AudioDeviceID) -> String? {
        string(kAudioObjectPropertyName, of: device)
    }

    static var processObjects: [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Listen here for output starts and stops: Core Audio does not notify `IsRunningOutput` changes, though it reports them when read.
    static let processRunningAddress = address(kAudioProcessPropertyIsRunning)

    static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = address(kAudioProcessPropertyIsRunningOutput)
        return (uint32(at: &address, of: process) ?? 0) != 0
    }

    static func pid(of process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        return uint32(at: &address, of: process).map { pid_t(bitPattern: $0) }
    }

    static func bundleIdentifier(of process: AudioObjectID) -> String? {
        string(kAudioProcessPropertyBundleID, of: process)
    }

    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static let volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    static let muteAddress = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)

    /// 0...1, nil when the device has no volume control (e.g. some HDMI outputs).
    static func volume(of device: AudioDeviceID) -> Float? {
        var address = volumeAddress
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress
        return uint32(at: &address, of: device) == 1
    }

    static func isVolumeSettable(_ device: AudioDeviceID) -> Bool {
        isSettable(volumeAddress, of: device)
    }

    /// False on devices that only expose per-channel mute, where setting the main element does nothing.
    static func isMuteSettable(_ device: AudioDeviceID) -> Bool {
        isSettable(muteAddress, of: device)
    }

    private static func isSettable(_ address: AudioObjectPropertyAddress, of device: AudioDeviceID) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func setVolume(_ volume: Float, of device: AudioDeviceID) {
        var address = volumeAddress
        var value = Float32(min(max(volume, 0), 1))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func setMuted(_ isMuted: Bool, of device: AudioDeviceID) {
        var address = muteAddress
        var value: UInt32 = isMuted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func uint32(at address: inout AudioObjectPropertyAddress, of object: AudioObjectID) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
