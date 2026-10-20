import CoreAudio
import Foundation

/// A private Core Audio tap on every process with one bundle ID, delivering mono samples on `queue`.
/// Needs the System Audio Recording permission; without it the tap delivers silence.
nonisolated final class ProcessAudioTap {
    /// One IO buffer of the tap, valid only during the handler call.
    struct Samples {
        fileprivate let buffers: UnsafeMutableAudioBufferListPointer
        fileprivate let encoding: SampleEncoding

        /// Calls `body` with every `stride`-th sample, as -1...1.
        func forEach(stride sampleStride: Int, _ body: (Double) -> Void) {
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                switch encoding {
                case .float32:
                    let samples = data.assumingMemoryBound(to: Float.self)
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    for index in stride(from: 0, to: count, by: sampleStride) {
                        body(Double(samples[index]))
                    }
                case .int16:
                    let samples = data.assumingMemoryBound(to: Int16.self)
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                    for index in stride(from: 0, to: count, by: sampleStride) {
                        body(Double(samples[index]) / Double(Int16.max))
                    }
                }
            }
        }
    }

    fileprivate enum SampleEncoding {
        case float32
        case int16
    }

    let sampleRate: Double

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// `bufferFrameSize` trades latency for fewer wake-ups; nil keeps the device default.
    init(
        bundleIdentifier: String,
        name: String,
        queue: DispatchQueue,
        bufferFrameSize: UInt32? = nil,
        handler: @escaping (Samples) -> Void
    ) throws {
        let description = CATapDescription(monoMixdownOfProcesses: [])
        description.name = name
        description.bundleIDs = [bundleIdentifier]
        description.isPrivate = true
        description.isProcessRestoreEnabled = true
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &tapID), operation: "Create process tap")
        let encoding: SampleEncoding
        do {
            (encoding, sampleRate) = try Self.format(of: tapID)
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
        self.tapID = tapID

        // From here on a throw runs deinit, which releases whatever was created.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: "com.ochurkin.BangBar.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString]
            ]
        ]
        try Self.check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID),
            operation: "Create aggregate device"
        )
        if var frames = bufferFrameSize {
            var address = SystemAudio.address(kAudioDevicePropertyBufferFrameSize)
            AudioObjectSetPropertyData(aggregateDeviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
        }
        try Self.check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, queue) { _, inputData, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
                handler(Samples(buffers: buffers, encoding: encoding))
            },
            operation: "Create audio callback"
        )
        try Self.check(AudioDeviceStart(aggregateDeviceID, ioProcID), operation: "Start audio capture")
    }

    deinit {
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
    }

    private static func format(of tapID: AudioObjectID) throws -> (SampleEncoding, Double) {
        var address = SystemAudio.address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), operation: "Read tap format")

        guard format.mFormatID == kAudioFormatLinearPCM else { throw ProcessAudioTapError.unsupportedFormat }
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 {
            return (.float32, format.mSampleRate)
        }
        if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0, format.mBitsPerChannel == 16 {
            return (.int16, format.mSampleRate)
        }
        throw ProcessAudioTapError.unsupportedFormat
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw ProcessAudioTapError.coreAudio(operation: operation, status: status)
        }
    }
}

private nonisolated enum ProcessAudioTapError: LocalizedError {
    case coreAudio(operation: String, status: OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .coreAudio(let operation, let status):
            "\(operation) returned OSStatus \(status)"
        case .unsupportedFormat:
            "The audio tap returned an unsupported sample format"
        }
    }
}

/// Tells when an app keeps its output stream running but plays nothing: browsers hold the stream open
/// for seconds after a pause, and may not close it at all between quick pauses.
nonisolated final class SilenceDetector: @unchecked Sendable {
    /// Paused streams carry exact zeros; dither in quiet audio is about 3e-5, well above this.
    private static let silenceThreshold = 1e-6
    private static let silenceDurationNanoseconds: UInt64 = 500_000_000
    private static let sampleStride = 8
    /// About 12 wake-ups a second at 48 kHz, plenty for a 0.5 s window.
    private static let bufferFrameSize: UInt32 = 4_096

    private let queue = DispatchQueue(label: "com.ochurkin.BangBar.silence", qos: .utility)
    // Owned by `queue`.
    private var tap: ProcessAudioTap?
    private var isInvalidated = false
    private var hasHeardSound = false
    private var silentSince: UInt64?
    private var reportedSilent = false

    /// Reports true after the app was heard and then played only silence for 0.5 s, and false when sound returns.
    /// Never reports when the tap hears nothing at all, for example without the System Audio Recording permission.
    /// The tap is created and destroyed on the detector's queue, because both block on coreaudiod.
    typealias ChangeHandler = @MainActor @Sendable (SilenceDetector, Bool) -> Void

    init(bundleIdentifier: String, onChange: @escaping ChangeHandler) {
        queue.async { [self] in
            guard !isInvalidated else { return }
            tap = try? ProcessAudioTap(
                bundleIdentifier: bundleIdentifier,
                name: "BangBar Silence",
                queue: queue,
                bufferFrameSize: Self.bufferFrameSize
            ) { [weak self] samples in
                self?.process(samples, onChange: onChange)
            }
        }
    }

    func invalidate() {
        queue.async { [self] in
            isInvalidated = true
            tap = nil
        }
    }

    private func process(_ samples: ProcessAudioTap.Samples, onChange: @escaping ChangeHandler) {
        guard !isInvalidated else { return }
        var peak = 0.0
        samples.forEach(stride: Self.sampleStride) { peak = max(peak, abs($0)) }

        let now = DispatchTime.now().uptimeNanoseconds
        let isSilent: Bool
        if peak > Self.silenceThreshold {
            hasHeardSound = true
            silentSince = nil
            isSilent = false
        } else {
            let since = silentSince ?? now
            silentSince = since
            isSilent = hasHeardSound && now - since >= Self.silenceDurationNanoseconds
        }
        guard isSilent != reportedSilent else { return }
        reportedSilent = isSilent
        Task { @MainActor [self] in onChange(self, isSilent) }
    }
}
