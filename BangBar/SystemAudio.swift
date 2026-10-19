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
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
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

    private static func uint32(at address: inout AudioObjectPropertyAddress, of object: AudioObjectID) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
