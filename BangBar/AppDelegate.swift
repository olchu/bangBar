import AppKit
import OSLog
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "BangBar", category: "PanelLifecycle")
    var statusItem: NSStatusItem?
    var hoverPanel: HoverPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hoverPollTimer: Timer?
    private var nextHoverOpenAttempt: TimeInterval = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var settingsWindow: NSWindow?
    private let calendarAlerts = CalendarAlertService()
    private let healthMonitor = AppHealthMonitor()
    private let keyboardSwitcher = KeyboardSwitcherService()
    private var compactExpansionGraceUntil: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        BangBarSettings.registerDefaults()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        setupHoverPanel()
        startMouseTracking()
        startWorkspaceTracking()
        calendarAlerts.start()
        keyboardSwitcher.start()
        healthMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMouseTracking()
        keyboardSwitcher.stop()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        applicationObservers.forEach(NotificationCenter.default.removeObserver)
        applicationObservers.removeAll()
        healthMonitor.markCleanShutdown()
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(named: "statusbar")
                ?? NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "BangBar")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true

            button.image = image
            button.action = #selector(statusBarClicked)
            button.target = self
        }
    }

    @objc func statusBarClicked() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Показать панель", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Panel Setup

    func setupHoverPanel() {
        hoverPanel = HoverPanel()
        hoverPanel?.onHoverEvent = { [weak self] event in
            self?.handleMouseMove(event)
        }
        hoverPanel?.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
    }

    // MARK: - Mouse Tracking

    func startMouseTracking() {
        stopMouseTracking()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .mouseEntered]) { [weak self] event in
            self?.handleMouseMove(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMove(event)
            return event
        }
        // Reevaluate a stationary pointer after an animation or a busy main run loop.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            self?.evaluateHover()
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        hoverPollTimer = timer
        logger.info("Mouse tracking started")
    }

    private func stopMouseTracking() {
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func startWorkspaceTracking() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recoverPanel(reason: "wake")
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recoverPanel(reason: "active-space-changed", isSpaceChange: true)
        })
        applicationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recoverPanel(reason: "screen-parameters-changed")
        })
    }

    private func recoverPanel(reason: String, isSpaceChange: Bool = false) {
        logger.notice("Recovering panel after \(reason, privacy: .public)")
        healthMonitor.checkpoint("panel-recovery-\(reason)")
        nextHoverOpenAttempt = 0
        compactExpansionGraceUntil = .distantPast
        startMouseTracking()
        if isSpaceChange {
            hoverPanel?.handleActiveSpaceChange(on: screenContainingMouse())
        } else {
            hoverPanel?.recoverAfterSystemTransition(on: screenContainingMouse())
        }
    }

    func handleMouseMove(_ event: NSEvent) {
        evaluateHover()
    }

    private func evaluateHover() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screenContainingMouse() else { return }
        let screenFrame = screen.frame
        let menuBarHeight = NSStatusBar.system.thickness

        let triggerZone: NSRect
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchX = leftArea.maxX
            let notchWidth = rightArea.minX - leftArea.maxX
            let notchHeight = leftArea.height
            triggerZone = NSRect(
                x: notchX,
                y: screenFrame.maxY - notchHeight,
                width: notchWidth,
                height: notchHeight
            )
        } else {
            let panelWidth = hoverPanel?.frame.width ?? 560
            triggerZone = NSRect(
                x: screenFrame.midX - panelWidth / 2,
                y: screenFrame.maxY - menuBarHeight,
                width: panelWidth,
                height: menuBarHeight
            )
        }

        let activationThreshold = BangBarSettings.panelActivationThreshold
        let activationZone = PanelActivationGeometry.zone(
            around: triggerZone,
            threshold: activationThreshold,
            screenFrame: screenFrame
        )
        let stableTriggerZone = triggerZone.insetBy(dx: -10, dy: -6)
        let isCompactMode = hoverPanel?.isCompactMode == true
        let panelIsOnMouseScreen = hoverPanel?.frame.intersects(screenFrame) == true
        let shouldOpenPanel = if isCompactMode && panelIsOnMouseScreen {
            hoverPanel?.containsCompactHoverPoint(
                mouseLocation,
                activationThreshold: activationThreshold
            ) == true
        } else {
            activationZone.contains(mouseLocation)
        }

        if shouldOpenPanel {
            if let panel = hoverPanel,
               (!panel.isVisible || panel.isHiding || panel.isCompactMode || !panel.isOnActiveSpace || !panelIsOnMouseScreen),
               ProcessInfo.processInfo.systemUptime >= nextHoverOpenAttempt {
                // Give WindowServer time to apply Space membership before retrying.
                nextHoverOpenAttempt = ProcessInfo.processInfo.systemUptime + 0.75
                if panel.isCompactMode {
                    compactExpansionGraceUntil = Date().addingTimeInterval(0.85)
                }
                logger.debug("Opening panel from hover; visible=\(panel.isVisible) hiding=\(panel.isHiding) compact=\(panel.isCompactMode)")
                healthMonitor.checkpoint("panel-open-hover")
                panel.slideIn(on: screen)
            }
        } else {
            if let panel = hoverPanel, panel.isVisible, !panel.isHiding {
                guard Date() >= compactExpansionGraceUntil else { return }

                let panelFrame = panel.frame
                let hoverFrame = panelFrame.insetBy(dx: -10, dy: -8)

                if !panel.isCompactMode,
                   !hoverFrame.contains(mouseLocation),
                   !stableTriggerZone.contains(mouseLocation) {
                    panel.slideOut()
                }
            }
        }
    }

    // MARK: - Actions

    @objc func showPanel() {
        logger.info("Opening panel from status menu")
        healthMonitor.checkpoint("panel-open-menu")
        hoverPanel?.slideIn(on: screenContainingMouse())
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
    }

    @objc func openSettings() {
        healthMonitor.checkpoint("settings-open")
        var isNewSettingsWindow = false

        if settingsWindow == nil {
            let initialContentSize = NSSize(width: 1180, height: 700)
            let window = NSWindow(
                contentRect: centeredSettingsContentRect(size: initialContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Настройки BangBar"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = .black
            window.isMovableByWindowBackground = false
            window.animationBehavior = .none
            window.minSize = NSSize(width: 960, height: 600)
            let clipboardHistory = hoverPanel?.clipboardHistory ?? ClipboardHistoryService()
            let hostingController = NSHostingController(
                rootView: SettingsView(clipboardHistory: clipboardHistory)
            )
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.black.cgColor
            window.contentViewController = hostingController
            applyBlackTitlebarBackground(to: window)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            centerSettingsWindow(window)
            isNewSettingsWindow = true
            settingsWindow = window
        }

        if let settingsWindow {
            NotificationCenter.default.post(name: .bangBarSettingsWillOpen, object: nil)
            NSApp.activate(ignoringOtherApps: true)
            centerSettingsWindow(settingsWindow)
            settingsWindow.makeKeyAndOrderFront(nil)

            if isNewSettingsWindow {
                DispatchQueue.main.async { [weak self, weak settingsWindow] in
                    guard let settingsWindow else { return }
                    self?.centerSettingsWindow(settingsWindow)
                    settingsWindow.alphaValue = 1
                }
            } else {
                settingsWindow.alphaValue = 1
            }
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func applyBlackTitlebarBackground(to window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }

        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = NSColor.black.cgColor
        updateVisualEffectViews(in: frameView)
    }

    private func centerSettingsWindow(_ window: NSWindow) {
        guard let screen = settingsWindowScreen(for: window) else {
            window.center()
            return
        }

        let screenFrame = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = screenFrame.midX - frame.width / 2
        frame.origin.y = screenFrame.midY - frame.height / 2
        frame.origin.x = min(max(frame.origin.x, screenFrame.minX), screenFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, screenFrame.minY), screenFrame.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    private func centeredSettingsContentRect(size: NSSize) -> NSRect {
        guard let screen = settingsTargetScreen() else {
            return NSRect(origin: .zero, size: size)
        }

        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }

    private func settingsWindowScreen(for window: NSWindow) -> NSScreen? {
        settingsTargetScreen() ?? window.screen ?? NSScreen.main
    }

    private func settingsTargetScreen() -> NSScreen? {
        statusItem?.button?.window?.screen ?? primarySettingsScreen()
    }

    private func primarySettingsScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            guard
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else {
                return false
            }

            return screenNumber.uint32Value == mainDisplayID
        }
    }

    private func updateVisualEffectViews(in view: NSView) {
        if let visualEffectView = view as? NSVisualEffectView {
            visualEffectView.material = .windowBackground
            visualEffectView.blendingMode = .withinWindow
            visualEffectView.state = .inactive
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.backgroundColor = NSColor.black.cgColor
        }

        for subview in view.subviews {
            updateVisualEffectViews(in: subview)
        }
    }
}
