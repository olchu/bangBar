import CoreAudio
import Foundation
import OSLog

nonisolated final class AudioLevelMonitor: @unchecked Sendable {
    typealias LevelHandler = @MainActor @Sendable ([Double]) -> Void

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

    private var tap: ProcessAudioTap?
    private var currentBundleIdentifier: String?
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
            let tap = try ProcessAudioTap(bundleIdentifier: bundleIdentifier, name: "BangBar Music Levels", queue: audioQueue) {
                [weak self] in self?.process($0)
            }
            effectiveSampleRate = tap.sampleRate / Double(Self.sampleStride)
            self.tap = tap
            currentBundleIdentifier = bundleIdentifier
        } catch {
            Self.logger.error("Audio level capture failed: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func stop() {
        tap = nil
        currentBundleIdentifier = nil
        sampleWindow.removeAll(keepingCapacity: true)
        lastUpdateTime = 0
        smoothedBands = [0.0, 0.0, 0.0, 0.0]
    }

    private func process(_ samples: ProcessAudioTap.Samples) {
        samples.forEach(stride: Self.sampleStride) { sampleWindow.append($0) }

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
}
