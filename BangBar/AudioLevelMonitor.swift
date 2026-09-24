import CoreAudio
import Foundation
import OSLog

nonisolated final class AudioLevelMonitor: @unchecked Sendable {
    typealias LevelHandler = @MainActor @Sendable ([Double]) -> Void

    private enum SampleEncoding {
        case float32
        case int16
    }

    private static let logger = Logger(subsystem: "BangBar", category: "AudioLevelMonitor")
    private static let updateIntervalNanoseconds: UInt64 = 80_000_000
    private static let sampleStride = 2
    private static let bandFrequencies: [[Double]] = [
        [80, 140, 220],
        [320, 500, 760],
        [1_050, 1_600, 2_400],
        [3_400, 5_000, 7_000]
    ]
    private static let bandGainDecibels = [0.0, 2.5, 5.0, 8.0]

    private let audioQueue = DispatchQueue(
        label: "com.ochurkin.BangBar.audio-levels",
        qos: .utility
    )
    private let levelHandler: LevelHandler

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var currentBundleIdentifier: String?
    private var sampleEncoding = SampleEncoding.float32
    private var effectiveSampleRate = 24_000.0

    private var sampleWindow: [Double] = []
    private var lastUpdateTime: UInt64 = 0
    private var smoothedBands = [0.0, 0.0, 0.0, 0.0]

    init(levelHandler: @escaping LevelHandler) {
        self.levelHandler = levelHandler
        sampleWindow.reserveCapacity(2_400)
    }

    deinit {
        stop()
    }

    func start(bundleIdentifier: String) {
        guard currentBundleIdentifier != bundleIdentifier else { return }
        stop()

        do {
            try createTap(bundleIdentifier: bundleIdentifier)
            currentBundleIdentifier = bundleIdentifier
        } catch {
            Self.logger.error("Audio level capture failed: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }

        currentBundleIdentifier = nil
        sampleWindow.removeAll(keepingCapacity: true)
        lastUpdateTime = 0
        smoothedBands = [0.0, 0.0, 0.0, 0.0]
    }

    private func createTap(bundleIdentifier: String) throws {
        let description = CATapDescription(monoMixdownOfProcesses: [])
        description.name = "BangBar Music Levels"
        description.bundleIDs = [bundleIdentifier]
        description.isPrivate = true
        description.isProcessRestoreEnabled = true
        description.muteBehavior = .unmuted

        try check(
            AudioHardwareCreateProcessTap(description, &tapID),
            operation: "Create process tap"
        )

        let format = try tapFormat(for: tapID)
        sampleEncoding = format.encoding
        effectiveSampleRate = format.sampleRate / Double(Self.sampleStride)

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "BangBar Music Levels",
            kAudioAggregateDeviceUIDKey: "com.ochurkin.BangBar.audio-levels.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString]
            ]
        ]

        try check(
            AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &aggregateDeviceID
            ),
            operation: "Create aggregate device"
        )

        var newIOProcID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(
                &newIOProcID,
                aggregateDeviceID,
                audioQueue
            ) { [weak self] _, inputData, _, _, _ in
                self?.process(inputData)
            },
            operation: "Create audio callback"
        )
        ioProcID = newIOProcID

        try check(
            AudioDeviceStart(aggregateDeviceID, newIOProcID),
            operation: "Start audio capture"
        )
    }

    private func tapFormat(
        for tapID: AudioObjectID
    ) throws -> (encoding: SampleEncoding, sampleRate: Double) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format),
            operation: "Read tap format"
        )

        guard format.mFormatID == kAudioFormatLinearPCM else {
            throw AudioLevelMonitorError.unsupportedFormat
        }
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
           format.mBitsPerChannel == 32 {
            return (.float32, format.mSampleRate)
        }
        if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
           format.mBitsPerChannel == 16 {
            return (.int16, format.mSampleRate)
        }
        throw AudioLevelMonitorError.unsupportedFormat
    }

    private func process(_ inputData: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        for buffer in bufferList {
            guard let data = buffer.mData else { continue }
            switch sampleEncoding {
            case .float32:
                let samples = data.assumingMemoryBound(to: Float.self)
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                for index in stride(from: 0, to: count, by: Self.sampleStride) {
                    sampleWindow.append(Double(samples[index]))
                }
            case .int16:
                let samples = data.assumingMemoryBound(to: Int16.self)
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                for index in stride(from: 0, to: count, by: Self.sampleStride) {
                    sampleWindow.append(Double(samples[index]) / Double(Int16.max))
                }
            }
        }

        let now = DispatchTime.now().uptimeNanoseconds
        guard lastUpdateTime == 0
                || now - lastUpdateTime >= Self.updateIntervalNanoseconds else {
            return
        }
        lastUpdateTime = now

        guard sampleWindow.count >= 128 else { return }
        let levels = measuredBands(from: sampleWindow)
        sampleWindow.removeAll(keepingCapacity: true)
        Task { @MainActor [levelHandler] in
            levelHandler(levels)
        }
    }

    private func measuredBands(from samples: [Double]) -> [Double] {
        for index in Self.bandFrequencies.indices {
            let frequencies = Self.bandFrequencies[index].filter {
                $0 < effectiveSampleRate * 0.48
            }
            guard !frequencies.isEmpty else {
                smoothedBands[index] = 0
                continue
            }

            let energy = frequencies.reduce(0.0) { partial, frequency in
                let magnitude = goertzelMagnitude(
                    samples: samples,
                    frequency: frequency,
                    sampleRate: effectiveSampleRate
                )
                return partial + magnitude * magnitude
            }
            let magnitude = sqrt(energy / Double(frequencies.count))
            let decibels = 20 * log10(max(magnitude, 0.000_001))
                + Self.bandGainDecibels[index]
            let normalized = min(max((decibels + 58) / 46, 0), 1)
            let contrasted = pow(normalized, 1.15)
            let smoothing = contrasted > smoothedBands[index] ? 0.72 : 0.28
            smoothedBands[index] += (contrasted - smoothedBands[index]) * smoothing
        }
        return smoothedBands
    }

    private func goertzelMagnitude(
        samples: [Double],
        frequency: Double,
        sampleRate: Double
    ) -> Double {
        let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
        var previous = 0.0
        var previousPrevious = 0.0

        for sample in samples {
            let current = sample + coefficient * previous - previousPrevious
            previousPrevious = previous
            previous = current
        }

        let power = max(
            previous * previous
                + previousPrevious * previousPrevious
                - coefficient * previous * previousPrevious,
            0
        )
        return 2 * sqrt(power) / Double(samples.count)
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioLevelMonitorError.coreAudio(operation: operation, status: status)
        }
    }
}

private enum AudioLevelMonitorError: LocalizedError {
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
