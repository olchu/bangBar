import AppKit
import CoreAudio

struct AudioApp: Equatable {
    let bundleIdentifier: String
    let name: String
    let processIdentifier: pid_t
    /// The process that actually plays, often a helper (`com.google.Chrome.helper`, `com.apple.WebKit.GPU`).
    let audioBundleIdentifier: String
}

/// Publishes the app playing audio through Core Audio, for apps that have no AppleScript player API.
final class AudioActivityMonitor {
    /// Skips notification sounds; the app must keep its output running this long to be shown.
    private static let startDelay: TimeInterval = 2
    /// Bridges the gap between two videos instead of collapsing the compact panel.
    private static let stopDelay: TimeInterval = 2

    var onChange: (() -> Void)?
    private(set) var playingApp: AudioApp? {
        didSet { onChange?() }
    }

    private var processListListener: AudioObjectPropertyListenerBlock?
    private var outputListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    /// Resolved on a process's first output and kept, because a process object never changes owner.
    /// nil for daemons, system sounds, players and BangBar.
    private var owners: [AudioObjectID: AudioApp?] = [:]
    private var runningProcesses: Set<AudioObjectID> = []
    /// Apps whose output is running now, with the time it started.
    private var runningApps: [String: (app: AudioApp, since: Date)] = [:]
    private var stoppedAt: Date?
    private var pendingUpdate: DispatchWorkItem?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    deinit {
        stop()
    }

    private func start() {
        var address = SystemAudio.address(kAudioHardwarePropertyProcessObjectList)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.processListChanged() }
        }
        guard AudioObjectAddPropertyListenerBlock(SystemAudio.systemObject, &address, .main, listener) == noErr
        else { return }
        processListListener = listener
        processListChanged()
    }

    private func stop() {
        if let processListListener {
            var address = SystemAudio.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(SystemAudio.systemObject, &address, .main, processListListener)
        }
        processListListener = nil
        for process in Array(outputListeners.keys) {
            removeOutputListener(from: process)
        }
        pendingUpdate?.cancel()
        pendingUpdate = nil
        runningApps = [:]
        stoppedAt = nil
        if playingApp != nil { playingApp = nil }
    }

    private func processListChanged() {
        let processes = Set(SystemAudio.processObjects)
        for process in outputListeners.keys where !processes.contains(process) {
            removeOutputListener(from: process)
        }
        // A process without a listener would never report its stop, so it is not tracked as running.
        for process in processes where outputListeners[process] == nil {
            if addOutputListener(to: process), SystemAudio.isRunningOutput(process) {
                runningProcesses.insert(process)
            }
        }
        runningProcessesChanged()
    }

    private func addOutputListener(to process: AudioObjectID) -> Bool {
        var address = SystemAudio.processRunningAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged(of: process) }
        }
        guard AudioObjectAddPropertyListenerBlock(process, &address, .main, listener) == noErr else { return false }
        outputListeners[process] = listener
        return true
    }

    private func removeOutputListener(from process: AudioObjectID) {
        runningProcesses.remove(process)
        owners[process] = nil
        guard let listener = outputListeners.removeValue(forKey: process) else { return }
        var address = SystemAudio.processRunningAddress
        AudioObjectRemovePropertyListenerBlock(process, &address, .main, listener)
    }

    private func outputChanged(of process: AudioObjectID) {
        if SystemAudio.isRunningOutput(process) {
            runningProcesses.insert(process)
        } else {
            runningProcesses.remove(process)
        }
        runningProcessesChanged()
    }

    private func runningProcessesChanged() {
        let now = Date()
        var running: [String: (app: AudioApp, since: Date)] = [:]
        // Sorted so an app with several playing processes keeps resolving to the same one.
        for process in runningProcesses.sorted() {
            guard let app = owner(of: process), running[app.bundleIdentifier] == nil else { continue }
            running[app.bundleIdentifier] = (app, runningApps[app.bundleIdentifier]?.since ?? now)
        }
        runningApps = running
        update()
    }

    private func owner(of process: AudioObjectID) -> AudioApp? {
        if let owner = owners[process] { return owner }
        let owner = Self.resolveOwner(of: process)
        owners[process] = .some(owner)
        return owner
    }

    private func update() {
        pendingUpdate?.cancel()
        pendingUpdate = nil
        let now = Date()

        // The shown app skips the start delay, so a restart within the stop delay keeps it shown.
        let shown = runningApps.values
            .filter { $0.app == playingApp || now.timeIntervalSince($0.since) >= Self.startDelay }
            .max { $0.since < $1.since }?.app
        if let shown {
            stoppedAt = nil
            if playingApp != shown { playingApp = shown }
        } else if playingApp != nil {
            if stoppedAt == nil { stoppedAt = now }
            if let stoppedAt, now.timeIntervalSince(stoppedAt) >= Self.stopDelay {
                self.stoppedAt = nil
                playingApp = nil
            }
        }

        // Output listeners fire only on start and stop, so the delays need their own wake-up.
        let pending = runningApps.values.map { $0.since.addingTimeInterval(Self.startDelay) }
            + [stoppedAt?.addingTimeInterval(Self.stopDelay)].compactMap { $0 }
        guard let next = pending.filter({ $0 > now }).min() else { return }
        let work = DispatchWorkItem { [weak self] in self?.update() }
        pendingUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + next.timeIntervalSince(now), execute: work)
    }

    private static func resolveOwner(of process: AudioObjectID) -> AudioApp? {
        guard let pid = SystemAudio.pid(of: process), pid > 0,
              let audioBundleID = SystemAudio.bundleIdentifier(of: process), !audioBundleID.isEmpty,
              let app = regularApp(owning: pid, bundleIdentifier: audioBundleID),
              let appBundleID = app.bundleIdentifier,
              MusicPlayer(bundleIdentifier: appBundleID) == nil,
              appBundleID != Bundle.main.bundleIdentifier else { return nil }
        return AudioApp(
            bundleIdentifier: appBundleID,
            name: app.localizedName ?? appBundleID,
            processIdentifier: app.processIdentifier,
            audioBundleIdentifier: audioBundleID
        )
    }

    private static func regularApp(owning pid: pid_t, bundleIdentifier: String) -> NSRunningApplication? {
        var ancestor = pid
        while ancestor > 1 {
            if let app = NSRunningApplication(processIdentifier: ancestor), app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentProcess(of: ancestor), parent != ancestor else { break }
            ancestor = parent
        }

        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        if let app = apps.first(where: { $0.bundleIdentifier.map { bundleIdentifier.hasPrefix($0 + ".") } ?? false }) {
            return app
        }
        // XPC services such as WebKit's GPU process are children of launchd but named after their app.
        guard let processName = NSRunningApplication(processIdentifier: pid)?.localizedName else { return nil }
        return apps
            .filter { $0.localizedName.map { !$0.isEmpty && processName.hasPrefix($0) } ?? false }
            .max { ($0.localizedName?.count ?? 0) < ($1.localizedName?.count ?? 0) }
    }

    private static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
