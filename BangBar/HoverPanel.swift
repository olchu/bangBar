import AppKit
import Combine
import OSLog
import SwiftUI

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private protocol PanelScrollHandling: AnyObject {
    func handlePanelScrollWheel(_ event: NSEvent) -> Bool
}

class HoverPanel: NSPanel {
    private let logger = Logger(subsystem: "BangBar", category: "HoverPanel")
    override var canBecomeKey: Bool { true }

    var isHiding = false
    var onHoverEvent: ((NSEvent) -> Void)?
    var onOpenSettings: (() -> Void)?
    private let state = PanelState()
    private let nowPlaying = NowPlayingService()
    private let pomodoro = PomodoroService()
    let clipboardHistory = ClipboardHistoryService()
    private let terminal = TerminalSessionService()
    /// AppKit, not SwiftUI: the expanded content is drawn with a `scaleEffect` that would blur terminal text.
    private let terminalContainer = FlippedView()
    private var hostingView: (NSView & PanelScrollHandling)?
    private var cancellables = Set<AnyCancellable>()
    private var hideWorkItem: DispatchWorkItem?
    private var artworkHeroCleanupWorkItem: DispatchWorkItem?
    private var frameAnimationTimer: Timer?
    private var transitionID = UUID()
    private var wantsExpandedPanel = false
    private static let spaceBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary
    ]
    private let hideDelay: TimeInterval = 0.45
    private var openedAt: Date = .distantPast

    var isCompactMode: Bool {
        state.isCompact
    }

    var isExpandedMode: Bool {
        isVisible && state.isExpanded && !state.isCompact
    }

    /// The compact strip's frame while it is shown, so a notice beside the notch can grow out of it.
    /// The settled frame rather than `frame`, which mid-animation is still the expanded panel or the notch.
    var compactPanelFrame: NSRect? {
        guard isVisible, state.isCompact, !state.isExpanded, !isHiding, let screen = screen ?? NSScreen.main
        else { return nil }
        return compactFrame(on: screen)
    }

    func setCompactContentCovered(_ covered: Bool) {
        state.compactContentCovered = covered
    }

    var isAnimatingFrame: Bool {
        frameAnimationTimer != nil
    }

    var isTerminalShown: Bool {
        isVisible && state.surface == .terminal && !isHiding
    }

    func containsCompactHoverPoint(
        _ screenPoint: NSPoint,
        activationThreshold: CGFloat
    ) -> Bool {
        guard state.isCompact else { return false }

        let localPoint = CGPoint(
            x: screenPoint.x - frame.minX,
            y: frame.maxY - screenPoint.y
        )
        let activationBounds = PanelActivationGeometry.localTopPinnedBounds(
            size: frame.size,
            threshold: activationThreshold
        )

        return NotchPanelShape()
            .path(in: activationBounds)
            .contains(localPoint)
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setupPanel()
    }

    convenience init() {
        let screen = NSScreen.main!
        let initialRect = PanelLayout.topCenteredFrame(
            width: PanelLayout.expandedWidth(forPage: 0, on: screen),
            height: PanelLayout.expandedHeight(on: screen),
            on: screen
        )
        self.init(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func setupPanel() {
        if let screen = NSScreen.main {
            state.topSafeInset = PanelLayout.topSafeInset(on: screen)
        }
        isFloatingPanel = true
        // SwiftUI and `animateFrame` draw every transition; AppKit's own fade on ordering in or out made the panel
        // vanish and leave ghosts.
        animationBehavior = .none
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = Self.spaceBehavior
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let hostingView = HoverHostingView(rootView: PanelContentView(
            state: state,
            nowPlaying: nowPlaying,
            pomodoro: pomodoro,
            clipboardHistory: clipboardHistory,
            terminal: terminal,
            onOpenSettings: { [weak self] in
                self?.onOpenSettings?()
            },
            onCloseTerminal: { [weak self] in
                self?.closeTerminal()
            }
        ))
        hostingView.onHoverEvent = { [weak self] event in
            self?.onHoverEvent?(event)
        }
        hostingView.shouldHandleVerticalSwipes = {
            UserDefaults.standard.bool(forKey: BangBarSettings.Key.clipboardSwipeNavigationEnabled)
                || UserDefaults.standard.bool(forKey: BangBarSettings.Key.terminalSwipeEnabled)
        }
        hostingView.onSwipeDown = { [weak self] in
            self?.handleVerticalSwipe(isDownward: true)
        }
        hostingView.onSwipeUp = { [weak self] in
            self?.handleVerticalSwipe(isDownward: false)
        }
        hostingView.shouldHandlePageSwipes = { [weak self] in
            guard let self else { return false }
            return self.state.isExpanded
                && !self.state.isCompact
                && self.state.surface == .widgets
                && !self.isAnimatingFrame
                && !PanelLayout.fittedWidgets(forPage: 1, on: self.screen ?? NSScreen.main).isEmpty
        }
        hostingView.onPageSwipeNext = { [weak self] in
            self?.handlePageSwipe(isNext: true)
        }
        hostingView.onPageSwipePrevious = { [weak self] in
            self?.handlePageSwipe(isNext: false)
        }
        hostingView.wantsLayer = true
        self.hostingView = hostingView

        // A sibling of the hosting view, not a subview: SwiftUI owns the hosting view's layer tree.
        let rootView = FlippedView()
        rootView.wantsLayer = true
        hostingView.frame = rootView.bounds
        hostingView.autoresizingMask = [.width, .height]
        rootView.addSubview(hostingView)

        terminalContainer.wantsLayer = true
        terminalContainer.layer?.cornerRadius = 10
        terminalContainer.layer?.cornerCurve = .continuous
        terminalContainer.layer?.masksToBounds = true
        terminalContainer.isHidden = true
        rootView.addSubview(terminalContainer)
        self.contentView = rootView
        terminal.onContentHeightChange = { [weak self] in
            self?.fitTerminalToContent()
        }
        terminal.onAllTabsClosed = { [weak self] in
            self?.closeTerminal()
        }

        nowPlaying.$info
            .combineLatest(nowPlaying.$isAvailable)
            .map { info, isAvailable in isAvailable && info.isPlaying }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlaying in
                self?.syncCompactVisibility(
                    isMusicPlaying: isPlaying,
                    isPomodoroRunning: self?.pomodoro.isRunning == true,
                    isCollectingImages: self?.clipboardHistory.isCollectingImages == true
                )
            }
            .store(in: &cancellables)

        pomodoro.$isRunning
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning in
                self?.syncCompactVisibility(
                    isMusicPlaying: self?.nowPlaying.isCurrentlyPlaying == true,
                    isPomodoroRunning: isRunning,
                    isCollectingImages: self?.clipboardHistory.isCollectingImages == true
                )
            }
            .store(in: &cancellables)

        clipboardHistory.$activeGroupID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] activeGroupID in
                self?.syncCompactVisibility(
                    isMusicPlaying: self?.nowPlaying.isCurrentlyPlaying == true,
                    isPomodoroRunning: self?.pomodoro.isRunning == true,
                    isCollectingImages: activeGroupID != nil
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeExpandedPanelForCurrentSettings()
            }
            .store(in: &cancellables)
    }

    override func orderOut(_ sender: Any?) {
        TooltipManager.shared.hide()
        super.orderOut(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        // Scrolling over the terminal moves its scrollback instead of switching surfaces.
        if event.type == .scrollWheel,
           !isOverTerminal(event.locationInWindow),
           let scrollHandler = hostingView,
           scrollHandler.handlePanelScrollWheel(event) {
            return
        }

        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        guard isTerminalShown else { return }
        // A click outside the panel took keyboard focus: that is how the terminal is dismissed.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isTerminalShown, !self.isKeyWindow else { return }
            self.slideOut()
        }
    }

    /// Surfaces stack vertically: Terminal ↑ Widgets ↓ Clipboard. The clipboard inversion swaps both directions.
    private func handleVerticalSwipe(isDownward: Bool) {
        guard state.isExpanded, state.contentVisible, !isAnimatingFrame else { return }

        let defaults = UserDefaults.standard
        let towardClipboard = isDownward != defaults.bool(forKey: BangBarSettings.Key.clipboardSwipeNavigationInverted)

        switch (state.surface, towardClipboard) {
        case (.terminal, true):
            closeTerminal()
        case (.widgets, false):
            if defaults.bool(forKey: BangBarSettings.Key.terminalSwipeEnabled) {
                showTerminal()
            }
        case (.widgets, true) where defaults.bool(forKey: BangBarSettings.Key.clipboardSwipeNavigationEnabled),
             (.clipboard, false):
            TooltipManager.shared.hide()
            withAnimation(.easeOut(duration: 0.16)) {
                state.surface = towardClipboard ? .clipboard : .widgets
            }
        default:
            break
        }
    }

    // MARK: - Terminal

    /// Read by the keyboard layout switcher's event tap: the panel is non-activating, so the frontmost app
    /// stays the previous one and its exclusion list does not cover typing in the terminal.
    var isTerminalFocused: Bool {
        isKeyWindow && state.surface == .terminal && terminal.hasKeyboardFocus
    }

    /// The global shortcut: opens the panel straight into the terminal, or closes it.
    func toggleTerminal(on preferredScreen: NSScreen?) {
        if isTerminalShown {
            slideOut()
        } else if canSwitchSurfaceInPlace, preferredScreen == nil || screen == preferredScreen {
            showTerminal()
        } else {
            state.surface = .terminal
            slideIn(on: preferredScreen)
        }
    }

    func terminateTerminal() {
        terminal.terminate()
    }

    private var canSwitchSurfaceInPlace: Bool {
        isExpandedMode && state.contentVisible && !isHiding && !isAnimatingFrame
    }

    private func showTerminal() {
        guard canSwitchSurfaceInPlace, state.surface != .terminal, let screen = screen ?? NSScreen.main else { return }

        TooltipManager.shared.hide()
        withAnimation(.easeOut(duration: 0.12)) {
            state.surface = .terminal
        }
        // The terminal appears after the frame settles, so its PTY is resized once rather than on every step.
        animateFrame(to: terminalFrame(on: screen), duration: 0.26) { [weak self] in
            self?.revealTerminal()
        }
    }

    /// Waits for the panel's expansion spring, which the AppKit terminal does not follow.
    private func revealTerminalAfterExpansion(transition: UUID) {
        guard state.surface == .terminal else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelLayout.expansionSpringSettleDelay) { [weak self] in
            guard let self, self.transitionID == transition else { return }
            self.revealTerminal()
        }
    }

    private func revealTerminal() {
        guard state.surface == .terminal, isVisible, !isHiding, !isAnimatingFrame else { return }

        layoutTerminalContainer()
        if terminalContainer.isHidden {
            terminalContainer.alphaValue = 0
            terminalContainer.isHidden = false
        }
        if terminalContainer.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                terminalContainer.animator().alphaValue = 1
            }
        }

        makeKey()
        let accentHex = UserDefaults.standard.string(forKey: BangBarSettings.Key.accentColorHex) ?? ""
        terminal.present(in: terminalContainer, accentColor: NSColor(Color(hex: accentHex)))
    }

    /// Back to the widgets; the shell keeps running.
    /// The reverse of `showTerminal`: the terminal fades out first, then the panel returns to the widget frame
    /// while the widgets fade in.
    private func closeTerminal() {
        guard state.surface == .terminal else { return }
        let transition = transitionID
        hideTerminalSurface(animated: true) { [weak self] in
            guard let self, self.transitionID == transition, self.state.surface == .terminal else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                self.state.surface = .widgets
            }
            guard self.isVisible, !self.isHiding, self.state.isExpanded,
                  let screen = self.screen ?? NSScreen.main else { return }
            self.animateFrame(to: self.expandedFrame(on: screen, page: self.state.currentPage), duration: 0.24)
        }
        relinquishKeyFocus()
    }

    /// Animated, the terminal fades out with the panel's content (`PanelLayout.contentFadeDuration`) and
    /// `completion` runs after it.
    private func hideTerminalSurface(animated: Bool = false, completion: (() -> Void)? = nil) {
        if let responder = firstResponder as? NSView, responder.isDescendant(of: terminalContainer) {
            makeFirstResponder(nil)
        }
        terminal.didHide()
        guard !terminalContainer.isHidden, animated else {
            terminalContainer.isHidden = true
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelLayout.contentFadeDuration
            terminalContainer.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // A reveal during the fade set the alpha back to 1.
            if let self, self.terminalContainer.alphaValue == 0 {
                self.terminalContainer.isHidden = true
            }
            completion?()
        }
    }

    /// The panel is non-activating, so the app the user was in stays active. Re-ordering the panel without
    /// making it key hands keyboard focus back to that app without hiding the panel.
    private func relinquishKeyFocus() {
        guard isKeyWindow else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    private func layoutTerminalContainer() {
        guard let contentView else { return }
        terminalContainer.frame = PanelLayout.terminalContentRect(
            in: contentView.bounds.size,
            topSafeInset: state.topSafeInset
        )
        let fullSize = CGSize(width: terminalContainer.frame.width, height: maxTerminalContentHeight)
        terminal.layoutSurfaces(size: fullSize, visibleHeight: terminalContainer.frame.height)
    }

    /// The panel follows the selected tab's rows in use, between one row and the maximum height.
    private func fitTerminalToContent() {
        guard state.surface == .terminal, isVisible, !isHiding, !terminalContainer.isHidden,
              let screen = screen ?? NSScreen.main else { return }
        let target = terminalFrame(on: screen)
        // Always restarts toward the latest target: comparing with `frame` alone would miss an animation
        // still heading for an older height.
        animateFrame(to: target, duration: 0.12) { [weak self] in
            self?.layoutTerminalContainer()
        }
    }

    private func isOverTerminal(_ windowPoint: NSPoint) -> Bool {
        guard !terminalContainer.isHidden else { return false }
        return terminalContainer.bounds.contains(terminalContainer.convert(windowPoint, from: nil))
    }

    /// Exactly `terminalMaxLines` rows: the PTY's size, and the most the panel ever shows.
    private var maxTerminalContentHeight: CGFloat {
        TerminalSurfaceView.contentHeight(rows: PanelLayout.terminalMaxLines)
    }

    private func terminalFrame(on screen: NSScreen) -> NSRect {
        PanelLayout.topCenteredFrame(
            width: PanelLayout.terminalWidth(forPage: state.currentPage, on: screen),
            height: PanelLayout.terminalPanelHeight(
                containerHeight: min(terminal.contentHeight, maxTerminalContentHeight),
                topSafeInset: PanelLayout.topSafeInset(on: screen)
            ),
            on: screen
        )
    }

    /// The frame of the expanded panel for the surface it currently shows.
    private func openFrame(on screen: NSScreen) -> NSRect {
        state.surface == .terminal ? terminalFrame(on: screen) : expandedFrame(on: screen, page: state.currentPage)
    }

    private func handlePageSwipe(isNext: Bool) {
        let isInverted = UserDefaults.standard.bool(forKey: BangBarSettings.Key.pageSwipeInverted)
        advancePage(by: (isNext != isInverted) ? 1 : -1)
    }

    private func advancePage(by delta: Int) {
        guard !isAnimatingFrame, let screen = screen ?? NSScreen.main else { return }
        let pageCount = PanelLayout.fittedWidgets(forPage: 1, on: screen).isEmpty ? 1 : 2
        let newPage = state.currentPage + delta
        guard newPage >= 0, newPage < pageCount else { return }

        TooltipManager.shared.suppressShowing(for: 0.5)

        let targetWidth = PanelLayout.expandedWidth(forPage: newPage, on: screen)
        let currentFrame = frame
        let targetFrame = NSRect(
            x: currentFrame.midX - targetWidth / 2,
            y: currentFrame.minY,
            width: targetWidth,
            height: currentFrame.height
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            state.currentPage = newPage
        }
        animateFrame(to: targetFrame, duration: 0.34)
    }

    // MARK: - Animation

    func slideIn(on preferredScreen: NSScreen? = nil) {
        wantsExpandedPanel = true
        cancelPendingTransition()
        let transition = transitionID
        TooltipManager.shared.suppressShowing(for: 0.7)
        isHiding = false
        openedAt = Date()
        hideWorkItem?.cancel()
        hideWorkItem = nil
        artworkHeroCleanupWorkItem?.cancel()
        artworkHeroCleanupWorkItem = nil
        state.compactArtworkRevealAllowed = true
        state.compactIndicatorRevealAllowed = true
        state.compactArtworkRevealAnimated = true

        guard let screen = preferredScreen ?? screen ?? NSScreen.main else {
            logger.error("Cannot show panel because no screen is available")
            return
        }

        state.topSafeInset = PanelLayout.topSafeInset(on: screen)
        if clipboardHistory.isCollectingImages, state.surface != .terminal {
            state.surface = .clipboard
            state.clipboardFilter = .images
        }
        let wasCompact = state.isCompact
        // The artwork hero flies into the now-playing widget, which the terminal covers.
        let wasNowPlayingCompact = state.compactContent == .nowPlaying && state.surface != .terminal
        let targetFrame = openFrame(on: screen)
        hideTerminalSurface()

        if !isVisible {
            state.isExpanded = false
            state.isCompact = false
            state.contentVisible = false
            setFrame(targetFrame, display: true)
            // Grows out of the notch at this frame's width, not the width the panel last closed from.
            state.collapsedScale = collapsedScale(on: screen)
        }
        presentOnActiveSpace(transition: transition)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.transitionID == transition else { return }
            if wasCompact, wasNowPlayingCompact {
                self.updateStateWithoutAnimation {
                    self.state.artworkHeroProgress = 0
                }
                self.state.compactArtworkRevealAllowed = false

                self.animateFrame(
                    to: targetFrame,
                    duration: 0.16,
                    progress: { [weak self] progress in
                        self?.state.artworkHeroProgress = progress
                    }
                ) { [weak self] in
                    guard let self else { return }
                    self.state.artworkHeroProgress = 1
                    self.state.isCompact = false
                    self.state.isExpanded = true
                    self.state.contentVisible = true
                    let cleanupWork = DispatchWorkItem { [weak self] in
                        guard let self, self.transitionID == transition else { return }
                        self.updateStateWithoutAnimation {
                            self.state.artworkHeroProgress = nil
                            self.state.compactArtworkRevealAllowed = true
                            self.state.compactArtworkRevealAnimated = true
                        }
                    }
                    self.artworkHeroCleanupWorkItem = cleanupWork
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: cleanupWork)
                }
            } else if wasCompact {
                self.state.artworkHeroProgress = nil
                self.animateFrame(to: targetFrame, duration: 0.18, completion: {
                    self.state.isCompact = false
                    self.state.isExpanded = true
                    self.state.contentVisible = true
                    self.revealTerminalAfterExpansion(transition: transition)
                })
            } else {
                self.state.artworkHeroProgress = nil
                self.state.isCompact = false
                self.state.isExpanded = true
                self.setFrame(targetFrame, display: true)
                self.state.contentVisible = true
                self.revealTerminalAfterExpansion(transition: transition)
            }
        }
    }

    private func cancelPendingTransition() {
        transitionID = UUID()
        ignoresMouseEvents = false
        frameAnimationTimer?.invalidate()
        frameAnimationTimer = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        artworkHeroCleanupWorkItem?.cancel()
        artworkHeroCleanupWorkItem = nil
        collectionBehavior = Self.spaceBehavior
    }

    func handleActiveSpaceChange(on preferredScreen: NSScreen?) {
        // The panel joins all Spaces, so a settled panel already followed the switch;
        // a full recovery here would replay its reveal animation.
        if isVisible, isOnActiveSpace, !isHiding, !isAnimatingFrame, screen != nil {
            return
        }
        recoverAfterSystemTransition(on: preferredScreen)
    }

    func recoverAfterSystemTransition(on preferredScreen: NSScreen?) {
        let restoreExpanded = wantsExpandedPanel
        let restoreCompact = clipboardHistory.isCollectingImages
            || pomodoro.isRunning || nowPlaying.isCurrentlyPlaying
        cancelPendingTransition()
        isHiding = false
        hideTerminalSurface()
        if !restoreExpanded {
            state.surface = .widgets
        }
        orderOut(nil)
        state.isExpanded = false
        state.isCompact = false
        state.contentVisible = false
        state.artworkHeroProgress = nil
        state.compactArtworkRevealAllowed = true
        state.compactIndicatorRevealAllowed = true
        level = .statusBar

        guard let targetScreen = preferredScreen ?? screen ?? NSScreen.main else { return }
        state.topSafeInset = PanelLayout.topSafeInset(on: targetScreen)
        setFrame(expandedFrame(on: targetScreen), display: false)
        if restoreExpanded {
            slideIn(on: targetScreen)
        } else if restoreCompact {
            enterCompactMode()
        }
        logger.notice("Panel state reset after system transition; visible=\(self.isVisible)")
    }

    private func presentOnActiveSpace(transition: UUID, attempt: Int = 0) {
        guard transitionID == transition else { return }
        // A hidden window can also belong to an inactive Space. Temporarily move
        // it on ordering, then restore the persistent all-Spaces overlay policy.
        if !isOnActiveSpace {
            orderOut(nil)
            collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary,
                                  .canJoinAllApplications, .stationary]
        }
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.transitionID == transition, self.isVisible else { return }
            self.collectionBehavior = Self.spaceBehavior
            if !self.isOnActiveSpace {
                if attempt < 2 {
                    self.presentOnActiveSpace(transition: transition, attempt: attempt + 1)
                } else {
                    self.logger.error("Panel failed to join active Space after presentation retries")
                }
            }
        }
    }

    /// Whether leaving the panel with the mouse should hide it: not mid-animation, not right after opening,
    /// and never while the terminal is shown.
    var dismissesOnHoverExit: Bool {
        !isAnimatingFrame && Date().timeIntervalSince(openedAt) > 0.5 && state.surface != .terminal
    }

    func slideOut() {
        let wasShowingTerminal = state.surface == .terminal
        // Last, after every state change below: re-ordering the window draws it at once, and an earlier draw
        // would show the widgets mid-switch.
        defer {
            if wasShowingTerminal {
                relinquishKeyFocus()
            }
        }
        hideTerminalSurface(animated: true)
        wantsExpandedPanel = false
        cancelPendingTransition()
        let transition = transitionID
        TooltipManager.shared.hide()
        isHiding = true
        state.contentVisible = false
        state.surface = .widgets
        state.currentPage = 0

        if clipboardHistory.isCollectingImages || pomodoro.isRunning || nowPlaying.isCurrentlyPlaying {
            enterCompactMode()
            return
        }

        // The reverse of opening: the black shape shrinks toward the notch (PanelContentView's collapse
        // animation) in a frame that stays put, so the window does not shrink underneath it as well. Meanwhile
        // the invisible rest of the window lets clicks through.
        state.collapsedScale = collapsedScale(on: screen ?? NSScreen.main)
        state.isExpanded = false
        state.isCompact = false
        state.artworkHeroProgress = nil
        ignoresMouseEvents = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.transitionID == transition else { return }
            if self.isHiding {
                let screen = self.screen ?? NSScreen.main
                self.orderOut(nil)
                self.isHiding = false
                // The hover trigger zone on displays without a notch is as wide as the hidden window.
                if let screen {
                    self.setFrame(self.compactFrame(on: screen), display: false)
                }
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }

    /// Shrinks the panel's black to the notch's width, where it disappears into the notch; displays without one
    /// keep a small strip that fades out.
    private func collapsedScale(on screen: NSScreen?) -> CGFloat {
        guard let screen, PanelLayout.notchRect(on: screen) != nil, frame.width > 0 else {
            return PanelLayout.hiddenPanelScale
        }
        return min(max(PanelLayout.concealedCompactWidth(on: screen) / frame.width, 0.05), PanelLayout.hiddenPanelScale)
    }

    private func expandedFrame(on screen: NSScreen, page: Int = 0) -> NSRect {
        PanelLayout.topCenteredFrame(
            width: PanelLayout.expandedWidth(forPage: page, on: screen),
            height: PanelLayout.expandedHeight(on: screen),
            on: screen
        )
    }

    private func resizeExpandedPanelForCurrentSettings() {
        guard isVisible, state.isExpanded, !isAnimatingFrame, let screen = screen ?? NSScreen.main else { return }
        state.topSafeInset = PanelLayout.topSafeInset(on: screen)
        let targetFrame = openFrame(on: screen)
        if frame != targetFrame {
            setFrame(targetFrame, display: true)
        }
        // Also when the frame is unchanged: a new maximum height resizes the tabs without moving the panel.
        if !terminalContainer.isHidden {
            layoutTerminalContainer()
        }
    }

    private func compactFrame(on screen: NSScreen) -> NSRect {
        PanelLayout.topCenteredFrame(width: compactWidth(on: screen), height: PanelLayout.compactHeight(on: screen), on: screen)
    }

    private func concealedCompactFrame(on screen: NSScreen) -> NSRect {
        PanelLayout.topCenteredFrame(width: PanelLayout.concealedCompactWidth(on: screen), height: PanelLayout.compactHeight(on: screen), on: screen)
    }

    private func compactWidth(on screen: NSScreen) -> CGFloat {
        let baseWidth = PanelLayout.compactWidth(on: screen)
        return clipboardHistory.isCollectingImages ? baseWidth + 110 : baseWidth
    }

    private func enterCompactMode() {
        wantsExpandedPanel = false
        TooltipManager.shared.hide()
        let nextCompactContent: PanelState.CompactContent = if clipboardHistory.isCollectingImages {
            .clipboardGroup
        } else if pomodoro.isRunning {
            .pomodoro
        } else {
            .nowPlaying
        }

        if isVisible, state.isCompact, !state.isExpanded, !isHiding {
            state.compactContent = nextCompactContent
            return
        }

        // Mid-collapse the window still has the expanded frame, so growing the strip from there would flash the
        // full-width black; it grows out of the notch as from hidden instead.
        let isCollapsing = isHiding && !state.isExpanded && !state.isCompact
        cancelPendingTransition()
        let transition = transitionID
        isHiding = false

        guard let screen = screen ?? NSScreen.main else { return }
        let targetFrame = compactFrame(on: screen)

        if !isVisible || isCollapsing {
            frameAnimationTimer?.invalidate()
            frameAnimationTimer = nil
            let startFrame = concealedCompactFrame(on: screen)
            updateStateWithoutAnimation {
                state.contentVisible = false
                state.isExpanded = false
                state.isCompact = true
                state.compactContent = nextCompactContent
                state.artworkHeroProgress = nil
                state.compactArtworkRevealAnimated = true
                state.compactArtworkRevealAllowed = false
                state.compactIndicatorRevealAllowed = false
            }
            setFrame(startFrame, display: false)
            contentView?.frame = NSRect(origin: .zero, size: startFrame.size)
            contentView?.layoutSubtreeIfNeeded()
            displayIfNeeded()
            presentOnActiveSpace(transition: transition)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.transitionID == transition else { return }
                self.setFrame(startFrame, display: false)
                self.animateFrame(to: targetFrame, duration: 0.24, completion: {
                    guard !self.isHiding else { return }
                    self.state.compactArtworkRevealAllowed = true
                    self.state.compactIndicatorRevealAllowed = true
                })
            }
        } else {
            let usesArtworkHero = nextCompactContent == .nowPlaying && nowPlaying.isAvailable
            state.contentVisible = false
            state.isExpanded = false
            state.artworkHeroProgress = usesArtworkHero ? 1 : nil
            state.compactContent = nextCompactContent
            state.compactArtworkRevealAnimated = false
            state.compactArtworkRevealAllowed = false
            state.compactIndicatorRevealAllowed = true
            state.isCompact = true
            animateFrame(
                to: targetFrame,
                duration: 0.24,
                progress: { [weak self] progress in
                    guard usesArtworkHero else { return }
                    self?.state.artworkHeroProgress = 1 - progress
                },
                completion: { [weak self] in
                    guard let self else { return }
                    self.updateStateWithoutAnimation {
                        self.state.compactArtworkRevealAllowed = true
                        self.state.artworkHeroProgress = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        guard self.transitionID == transition else { return }
                        self.state.compactArtworkRevealAnimated = true
                    }
                }
            )
        }
    }

    private func syncCompactVisibility(
        isMusicPlaying: Bool,
        isPomodoroRunning: Bool,
        isCollectingImages: Bool
    ) {
        if isCollectingImages || isPomodoroRunning || isMusicPlaying {
            state.compactContent = if isCollectingImages {
                .clipboardGroup
            } else if isPomodoroRunning {
                .pomodoro
            } else {
                .nowPlaying
            }
            if !isVisible || isHiding {
                enterCompactMode()
            } else if state.isCompact, let screen = screen ?? NSScreen.main, !isAnimatingFrame {
                animateFrame(to: compactFrame(on: screen), duration: 0.18)
            }
        } else if state.isCompact {
            exitCompactMode()
        }
    }

    private func exitCompactMode() {
        wantsExpandedPanel = false
        cancelPendingTransition()
        let transition = transitionID
        isHiding = true

        guard let screen = screen ?? NSScreen.main else {
            orderOut(nil)
            isHiding = false
            updateStateWithoutAnimation {
                state.isCompact = false
                state.artworkHeroProgress = nil
                state.compactArtworkRevealAnimated = true
                state.compactArtworkRevealAllowed = true
                state.compactIndicatorRevealAllowed = true
            }
            return
        }

        state.contentVisible = false
        state.isExpanded = false
        state.artworkHeroProgress = nil
        state.compactArtworkRevealAnimated = true
        state.compactArtworkRevealAllowed = false
        state.compactIndicatorRevealAllowed = false
        state.isCompact = true

        let compactFrame = compactFrame(on: screen)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.transitionID == transition else { return }
            guard self.isHiding,
                  !self.clipboardHistory.isCollectingImages,
                  !self.nowPlaying.isCurrentlyPlaying,
                  !self.pomodoro.isRunning else { return }

            self.animateFrame(to: self.concealedCompactFrame(on: screen), duration: 0.24, completion: { [weak self] in
                guard let self else { return }
                if self.isHiding,
                   !self.clipboardHistory.isCollectingImages,
                   !self.nowPlaying.isCurrentlyPlaying,
                   !self.pomodoro.isRunning {
                    self.orderOut(nil)
                    self.isHiding = false
                    self.updateStateWithoutAnimation {
                        self.state.isCompact = false
                        self.state.compactArtworkRevealAllowed = true
                        self.state.compactIndicatorRevealAllowed = true
                    }
                    self.setFrame(compactFrame, display: false)
                }
            })
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func animateFrame(
        to frame: NSRect,
        duration: TimeInterval,
        progress progressHandler: ((CGFloat) -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        frameAnimationTimer?.invalidate()
        frameAnimationTimer = nil
        guard self.frame != frame else {
            progressHandler?(1)
            completion?()
            return
        }
        let transition = transitionID

        let startFrame = self.frame
        let topY = frame.maxY
        let startTime = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, self.transitionID == transition else {
                timer.invalidate()
                return
            }

            let progress = min((CACurrentMediaTime() - startTime) / duration, 1)
            let easedProgress = 0.5 - 0.5 * cos(progress * .pi)
            progressHandler?(CGFloat(easedProgress))

            let width = interpolate(from: startFrame.width, to: frame.width, progress: easedProgress)
            let height = interpolate(from: startFrame.height, to: frame.height, progress: easedProgress)
            let midX = interpolate(from: startFrame.midX, to: frame.midX, progress: easedProgress)
            let nextFrame = NSRect(
                x: midX - width / 2,
                y: topY - height,
                width: width,
                height: height
            )

            self.setFramePinnedToTop(nextFrame, topY: topY)

            if progress >= 1 {
                progressHandler?(1)
                self.setFramePinnedToTop(frame, topY: topY)
                timer.invalidate()
                self.frameAnimationTimer = nil
                completion?()
            }
        }

        frameAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func interpolate(from start: CGFloat, to end: CGFloat, progress: Double) -> CGFloat {
        start + (end - start) * CGFloat(progress)
    }

    private func updateStateWithoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    private func setFramePinnedToTop(_ frame: NSRect, topY: CGFloat) {
        setFrame(frame, display: false)
        setFrameTopLeftPoint(CGPoint(x: frame.minX, y: topY))
        if !terminalContainer.isHidden {
            layoutTerminalContainer()
        }
        displayIfNeeded()
    }
}

final class HoverHostingView<Content: View>: NSHostingView<Content>, PanelScrollHandling {
    var onHoverEvent: ((NSEvent) -> Void)?
    var shouldHandleVerticalSwipes: (() -> Bool)?
    var onSwipeDown: (() -> Void)?
    var onSwipeUp: (() -> Void)?
    var shouldHandlePageSwipes: (() -> Bool)?
    var onPageSwipeNext: (() -> Void)?
    var onPageSwipePrevious: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var verticalSwipeDistance: CGFloat = 0
    private var didTriggerVerticalSwipe = false
    private var horizontalSwipeDistance: CGFloat = 0
    private var didTriggerHorizontalSwipe = false
    private let swipeActivationDistance: CGFloat = 42

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverEvent?(event)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverEvent?(event)
        super.mouseMoved(with: event)
    }

    func handlePanelScrollWheel(_ event: NSEvent) -> Bool {
        let handleVertical = shouldHandleVerticalSwipes?() == true
        let handlePaging = shouldHandlePageSwipes?() == true

        guard event.hasPreciseScrollingDeltas,
              event.momentumPhase.isEmpty,
              handleVertical || handlePaging,
              !containsSwipeExclusion(at: event.locationInWindow),
              !isInsideVerticalScrollView(at: event.locationInWindow) else {
            resetSwipeTrackingIfNeeded(for: event)
            return false
        }

        if event.phase.contains(.began) {
            verticalSwipeDistance = 0
            didTriggerVerticalSwipe = false
            horizontalSwipeDistance = 0
            didTriggerHorizontalSwipe = false
            TooltipManager.shared.hide()
        }

        if handleVertical, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let deviceNormalizedDelta = event.isDirectionInvertedFromDevice
                ? -event.scrollingDeltaY
                : event.scrollingDeltaY
            verticalSwipeDistance += deviceNormalizedDelta

            if !didTriggerVerticalSwipe,
               verticalSwipeDistance >= swipeActivationDistance {
                didTriggerVerticalSwipe = true
                onSwipeDown?()
            } else if !didTriggerVerticalSwipe,
                      verticalSwipeDistance <= -swipeActivationDistance {
                didTriggerVerticalSwipe = true
                onSwipeUp?()
            }

            resetSwipeTrackingIfNeeded(for: event)
            return true
        }

        if handlePaging, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            let deviceNormalizedDelta = event.isDirectionInvertedFromDevice
                ? -event.scrollingDeltaX
                : event.scrollingDeltaX
            horizontalSwipeDistance += deviceNormalizedDelta

            if !didTriggerHorizontalSwipe,
               horizontalSwipeDistance <= -swipeActivationDistance {
                didTriggerHorizontalSwipe = true
                onPageSwipeNext?()
            } else if !didTriggerHorizontalSwipe,
                      horizontalSwipeDistance >= swipeActivationDistance {
                didTriggerHorizontalSwipe = true
                onPageSwipePrevious?()
            }

            resetSwipeTrackingIfNeeded(for: event)
            return true
        }

        resetSwipeTrackingIfNeeded(for: event)
        return false
    }

    private func isInsideVerticalScrollView(at windowPoint: NSPoint) -> Bool {
        var view = hitTest(convert(windowPoint, from: nil))

        while let currentView = view {
            if let scrollView = currentView as? NSScrollView {
                return scrollView.hasVerticalScroller
            }
            view = currentView.superview
        }

        return false
    }

    private func containsSwipeExclusion(at windowPoint: NSPoint) -> Bool {
        containsSwipeExclusion(in: self, at: windowPoint)
    }

    private func containsSwipeExclusion(in view: NSView, at windowPoint: NSPoint) -> Bool {
        for subview in view.subviews {
            if subview is PanelSwipeExclusionView,
               subview.bounds.contains(subview.convert(windowPoint, from: nil)) {
                return true
            }

            if containsSwipeExclusion(in: subview, at: windowPoint) {
                return true
            }
        }

        return false
    }

    private func resetSwipeTrackingIfNeeded(for event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            verticalSwipeDistance = 0
            didTriggerVerticalSwipe = false
            horizontalSwipeDistance = 0
            didTriggerHorizontalSwipe = false
        }
    }
}
