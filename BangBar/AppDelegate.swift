import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hoverPanel: HoverPanel?
    var mouseMonitor: Any?
    private var compactExpansionGraceUntil: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        setupHoverPanel()
        startMouseTracking()
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "BangBar")
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
    }

    // MARK: - Mouse Tracking

    func startMouseTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .mouseEntered]) { [weak self] event in
            self?.handleMouseMove(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMove(event)
            return event
        }
    }

    func handleMouseMove(_ event: NSEvent) {
        guard let screen = NSScreen.main else { return }
        let mouseLocation = NSEvent.mouseLocation
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

        let stableTriggerZone = triggerZone.insetBy(dx: -10, dy: -6)
        let isCompactMode = hoverPanel?.isCompactMode == true
        let compactActivationFrame = hoverPanel?.frame.insetBy(dx: -10, dy: -10) ?? .zero
        let shouldOpenPanel = if isCompactMode {
            compactActivationFrame.contains(mouseLocation)
                || hoverPanel?.containsCompactHoverPoint(mouseLocation) == true
                || stableTriggerZone.contains(mouseLocation)
        } else {
            triggerZone.contains(mouseLocation)
        }

        if shouldOpenPanel {
            if let panel = hoverPanel,
               (!panel.isVisible || panel.isHiding || panel.isCompactMode),
               !panel.isAnimatingFrame {
                if panel.isCompactMode {
                    compactExpansionGraceUntil = Date().addingTimeInterval(0.85)
                }
                panel.slideIn()
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
        hoverPanel?.slideIn()
    }

    @objc func openSettings() {
        // TODO: settings window
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
