import AppKit
import OSLog

/// Not an `Unmanaged<CGEvent>?`: a nil meaning "swallow" is too easy to confuse with the nil of `self?.handle(...)`.
enum EventTapDecision {
    case pass
    case swallow
}

/// A session event tap on the main run loop. While `isEnabled` it installs as soon as Accessibility is granted,
/// removes itself when Accessibility is revoked (polling for both), and turns itself back on when macOS disables
/// it after a slow callback.
final class EventTap {
    typealias Handler = (_ type: CGEventType, _ event: CGEvent, _ proxy: CGEventTapProxy) -> EventTapDecision

    private static let logger = Logger(subsystem: "BangBar", category: "EventTap")

    private let name: String
    private let mask: CGEventMask
    private let handler: Handler
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            update()
        }
    }

    /// Called with `true` once the tap is really installed and with `false` when it is removed.
    var onInstalledChange: ((Bool) -> Void)?

    var isInstalled: Bool { tap != nil }

    init(name: String, mask: CGEventMask, handler: @escaping Handler) {
        self.name = name
        self.mask = mask
        self.handler = handler
    }

    static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }

    deinit {
        permissionTimer?.invalidate()
        remove()
    }

    private func update() {
        guard isEnabled else {
            stopPermissionPolling()
            remove()
            return
        }
        // Revoking Accessibility stops event delivery without telling the tap, so trust stays watched once installed.
        if AccessibilityAccess.isTrusted {
            install()
        } else {
            remove()
        }
        startPermissionPolling()
    }

    private func install() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let eventTap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { eventTap.handle(type: type, event: event, proxy: proxy) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.logger.error("Failed to create the \(self.name, privacy: .public) event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        onInstalledChange?(true)
    }

    private func remove() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.tap = nil
        runLoopSource = nil
        onInstalledChange?(false)
    }

    private func handle(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        return handler(type, event, proxy) == .swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = 1
        permissionTimer = timer
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}
