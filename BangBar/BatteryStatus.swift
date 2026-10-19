import Foundation
import IOKit.ps

nonisolated struct BatteryStatus: Equatable {
    let level: Int
    let isCharging: Bool
    let isCharged: Bool
    let isOnPowerAdapter: Bool

    static func symbolName(level: Int?, isCharging: Bool) -> String {
        if isCharging { return "battery.100percent.bolt" }
        guard let level else { return "battery.0percent" }
        if level > 75 { return "battery.100percent" }
        if level > 40 { return "battery.50percent" }
        if level > 15 { return "battery.25percent" }
        return "battery.0percent"
    }

    /// The internal battery; nil on Macs without one.
    static func current() -> BatteryStatus? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0
            else { continue }

            return BatteryStatus(
                level: min(100, Int((Double(current) / Double(maximum) * 100).rounded())),
                isCharging: description[kIOPSIsChargingKey as String] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey as String] as? Bool ?? false,
                isOnPowerAdapter: description[kIOPSPowerSourceStateKey as String] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }
}
