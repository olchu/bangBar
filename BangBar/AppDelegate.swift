import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hoverPanel: HoverPanel?
    var mouseMonitor: Any?
    var hideTimer: Timer?

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

        let panelWidth = hoverPanel?.frame.width ?? 560
        let triggerZone = NSRect(
            x: (screenFrame.width - panelWidth) / 2,
            y: screenFrame.maxY - menuBarHeight,
            width: panelWidth,
            height: menuBarHeight
        )

        if triggerZone.contains(mouseLocation) {
            hideTimer?.invalidate()
            hideTimer = nil
            if !(hoverPanel?.isVisible ?? false) || hoverPanel?.isHiding == true {
                hoverPanel?.slideIn()
            }
        } else {
            if let panel = hoverPanel, panel.isVisible {
                let panelFrame = panel.frame
                if !panelFrame.contains(mouseLocation) {
                    if hideTimer == nil {
                        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                            self?.hoverPanel?.slideOut()
                            self?.hideTimer = nil
                        }
                    }
                } else {
                    hideTimer?.invalidate()
                    hideTimer = nil
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
