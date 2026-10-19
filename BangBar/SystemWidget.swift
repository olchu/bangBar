import AppKit
import Combine
import Darwin
import SwiftUI

struct SystemWidget: View {
    let isActive: Bool
    @StateObject private var metrics = SystemMetricsService()
    @AppStorage(BangBarSettings.Key.accentColorHex) private var accentColorHex = BangBarSettings.defaultAccentColorHex
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text(batteryLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))

                Spacer()

                PulsingStatusDot(color: statusColor, isPulsing: isPulsing)

                Text(metrics.statusLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(height: 18)

            HStack(spacing: 7) {
                SystemMetricCard(
                    title: "CPU",
                    value: metrics.cpuLabel,
                    history: metrics.cpuHistory,
                    color: accentColor,
                    isPulsing: isPulsing
                )

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 38)

                SystemMetricCard(
                    title: "RAM",
                    value: metrics.memoryLabel,
                    history: metrics.memoryHistory,
                    color: accentColor,
                    isPulsing: isPulsing
                )
            }
            .frame(height: 57)

            HStack(spacing: 5) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 14)

                Text(diskLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: copyIPAddress) {
                    HStack(spacing: 4) {
                        Image(systemName: metrics.ipAddress == nil ? "wifi.slash" : "network")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accentColor)
                        Text(metrics.ipAddress ?? "Offline")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(metrics.ipAddress == nil ? statusColor : .white.opacity(0.72))
                }
                .buttonStyle(.plain)
                .disabled(metrics.ipAddress == nil)
                .help(metrics.ipAddress == nil ? "No active IPv4 address" : "Copy local IP address")
            }
            .foregroundStyle(.white.opacity(0.72))
            .frame(height: 17)
        }
        .frame(width: PanelLayout.systemWidgetWidth, height: PanelLayout.nowPlayingWidgetHeight)
        .onAppear {
            updateActivity()
        }
        .onChange(of: isActive) { _, _ in
            updateActivity()
        }
        .onDisappear {
            metrics.stop()
            isPulsing = false
        }
    }

    private var accentColor: Color { Color(hex: accentColorHex) }

    private var statusColor: Color {
        metrics.needsAttention ? .orange : accentColor
    }

    private var batterySymbol: String {
        BatteryStatus.symbolName(level: metrics.batteryLevel, isCharging: metrics.isCharging)
    }

    private var batteryLabel: String {
        if let batteryLevel = metrics.batteryLevel {
            return "\(batteryLevel)%\(metrics.isCharging ? " ⚡" : "")"
        }
        return "—"
    }

    private var diskLabel: String {
        return "\(metrics.diskFreeGB)GB"
    }

    private func updateActivity() {
        guard isActive else {
            metrics.stop()
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPulsing = false
            }
            return
        }

        metrics.start()
        guard !isPulsing else { return }
        withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    private func copyIPAddress() {
        guard let ipAddress = metrics.ipAddress else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ipAddress, forType: .string)
    }
}

private struct PulsingStatusDot: View {
    let color: Color
    let isPulsing: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(isPulsing ? 0.16 : 0.42), lineWidth: 1)
                .frame(width: 19, height: 19)
                .scaleEffect(isPulsing ? 1.32 : 0.9)

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(isPulsing ? 0.9 : 0.45), radius: isPulsing ? 7 : 3)
        }
        .frame(width: 22, height: 22)
    }
}

private struct SystemMetricCard: View {
    let title: String
    let value: String
    let history: [Double]
    let color: Color
    let isPulsing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))

                Spacer(minLength: 2)

                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
            }

            MetricSparkline(values: history, color: color, isPulsing: isPulsing)
        }
    }
}

private struct MetricSparkline: View {
    let values: [Double]
    let color: Color
    let isPulsing: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MetricDotGrid()

                SparklineAreaShape(values: values)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.34), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                SparklineShape(values: values)
                    .stroke(color.opacity(isPulsing ? 0.78 : 1), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(isPulsing ? 0.32 : 0.62), radius: isPulsing ? 2 : 4)

                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .shadow(color: color.opacity(0.9), radius: isPulsing ? 5 : 2)
                    .position(endpoint(in: geometry.size))
            }
        }
        .animation(.easeOut(duration: 0.35), value: values)
    }

    private func endpoint(in size: CGSize) -> CGPoint {
        let value = min(max(values.last ?? 0, 0), 100)
        return CGPoint(x: max(2, size.width - 2), y: max(2, min(size.height - 2, size.height * (1 - value / 100))))
    }
}

private struct MetricDotGrid: View {
    private let spacing: CGFloat = 8
    private let dotSize: CGFloat = 1.25

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y = spacing / 2

            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(
                        in: CGRect(
                            x: x - dotSize / 2,
                            y: y - dotSize / 2,
                            width: dotSize,
                            height: dotSize
                        )
                    )
                    x += spacing
                }
                y += spacing
            }

            context.fill(dots, with: .color(.white.opacity(0.24)))
        }
        .allowsHitTesting(false)
    }
}

private struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard !values.isEmpty else { return Path() }
        var path = Path()
        for (index, value) in values.enumerated() {
            let point = sparklinePoint(index: index, value: value, count: values.count, rect: rect)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

private struct SparklineAreaShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard !values.isEmpty else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (index, value) in values.enumerated() {
            path.addLine(to: sparklinePoint(index: index, value: value, count: values.count, rect: rect))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private func sparklinePoint(index: Int, value: Double, count: Int, rect: CGRect) -> CGPoint {
    let x = count > 1 ? rect.width * CGFloat(index) / CGFloat(count - 1) : rect.maxX
    let normalizedValue = min(max(value, 0), 100) / 100
    let y = rect.height * CGFloat(1 - normalizedValue)
    return CGPoint(x: x, y: y)
}

@MainActor
final class SystemMetricsService: NSObject, ObservableObject {
    @Published private(set) var cpuUsage = 0
    @Published private(set) var memoryUsage = 0
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var diskFreeGB = 0
    @Published private(set) var ipAddress: String?
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var cpuHistory: [Double] = [0]
    @Published private(set) var memoryHistory: [Double] = [0]

    private var timer: Timer?
    private var previousCPUTicks: [UInt64]?
    private var lastAuxiliaryRefresh: Date?
    private var lastDiskRefresh: Date?

    var cpuLabel: String { "\(cpuUsage)%" }
    var memoryLabel: String { "\(memoryUsage)%" }

    var needsAttention: Bool { statusLabel != "GOOD" }

    var statusLabel: String {
        switch thermalState {
        case .serious: return "WARM"
        case .critical: return "HOT"
        default:
            if ipAddress == nil { return "OFFLINE" }
            if let batteryLevel, batteryLevel <= 15 { return "LOW BAT" }
            if diskFreeGB < 10 { return "LOW DISK" }
            if cpuUsage >= 90 { return "CPU HIGH" }
            if memoryUsage >= 90 { return "RAM HIGH" }
            return "GOOD"
        }
    }

    func start() {
        guard timer == nil else { return }
        refresh(forceSlowMetrics: true)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh(forceSlowMetrics: Bool = false) {
        let now = Date()
        cpuUsage = readCPUUsage()
        memoryUsage = Self.readMemoryUsage()
        append(Double(cpuUsage), to: &cpuHistory)
        append(Double(memoryUsage), to: &memoryHistory)
        thermalState = ProcessInfo.processInfo.thermalState

        if forceSlowMetrics
            || lastAuxiliaryRefresh.map({ now.timeIntervalSince($0) >= 30 }) != false {
            let battery = BatteryStatus.current()
            batteryLevel = battery?.level
            isCharging = battery?.isCharging ?? false
            ipAddress = Self.readLocalIPv4Address()
            lastAuxiliaryRefresh = now
        }

        if forceSlowMetrics
            || lastDiskRefresh.map({ now.timeIntervalSince($0) >= 5 * 60 }) != false {
            diskFreeGB = Self.readDiskFreeGB()
            lastDiskRefresh = now
        }
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 24 {
            history.removeFirst(history.count - 24)
        }
    }

    private func readCPUUsage() -> Int {
        guard let ticks = Self.readCPUTicks() else { return cpuUsage }
        defer { previousCPUTicks = ticks }
        guard let previousCPUTicks else { return 0 }

        let deltas = zip(ticks, previousCPUTicks).map { current, previous in
            current >= previous ? current - previous : 0
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return cpuUsage }
        let idle = deltas[Int(CPU_STATE_IDLE)]
        return Int(((Double(total - idle) / Double(total)) * 100).rounded())
    }

    private static func readCPUTicks() -> [UInt64]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3].map(UInt64.init)
    }

    private static func readMemoryUsage() -> Int {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        guard totalMemory > 0 else { return 0 }
        return min(100, Int((Double(usedPages * pageSize) / Double(totalMemory) * 100).rounded()))
    }

    private static func readDiskFreeGB() -> Int {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values?.volumeAvailableCapacityForImportantUsage else { return 0 }
        return max(0, Int(bytes / 1_000_000_000))
    }

    private static func readLocalIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var candidates: [(priority: Int, address: String)] = []
        var interface = firstInterface
        while true {
            let value = interface.pointee
            if let address = value.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET),
               value.ifa_flags & UInt32(IFF_UP) != 0,
               value.ifa_flags & UInt32(IFF_LOOPBACK) == 0 {
                let name = String(cString: value.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let priority = name == "en0" ? 0 : (name.hasPrefix("en") ? 1 : 2)
                    candidates.append((priority, String(cString: host)))
                }
            }

            guard let next = value.ifa_next else { break }
            interface = next
        }
        return candidates.min { $0.priority < $1.priority }?.address
    }
}
