import AppKit
import Combine
import OSLog
import SwiftUI

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

    var isAnimatingFrame: Bool {
        frameAnimationTimer != nil
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
        let expandedWidth = PanelLayout.expandedWidth(forPage: 0, on: screen)
        let initialRect = NSRect(
            x: screen.frame.midX - expandedWidth / 2,
            y: screen.frame.maxY - PanelLayout.expandedHeight(on: screen),
            width: expandedWidth,
            height: PanelLayout.expandedHeight(on: screen)
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

        let contentView = HoverHostingView(rootView: PanelContentView(
            state: state,
            nowPlaying: nowPlaying,
            pomodoro: pomodoro,
            clipboardHistory: clipboardHistory,
            onOpenSettings: { [weak self] in
                self?.onOpenSettings?()
            }
        ))
        contentView.onHoverEvent = { [weak self] event in
            self?.onHoverEvent?(event)
        }
        contentView.shouldHandleVerticalSwipes = {
            UserDefaults.standard.bool(
                forKey: BangBarSettings.Key.clipboardSwipeNavigationEnabled
            )
        }
        contentView.onSwipeDown = { [weak self] in
            self?.handleClipboardSwipe(isDownward: true)
        }
        contentView.onSwipeUp = { [weak self] in
            self?.handleClipboardSwipe(isDownward: false)
        }
        contentView.shouldHandlePageSwipes = { [weak self] in
            guard let self else { return false }
            return self.state.isExpanded
                && !self.state.isCompact
                && !self.state.showsClipboardHistory
                && !self.isAnimatingFrame
                && !PanelLayout.fittedWidgets(forPage: 1, on: self.screen ?? NSScreen.main).isEmpty
        }
        contentView.onPageSwipeNext = { [weak self] in
            self?.handlePageSwipe(isNext: true)
        }
        contentView.onPageSwipePrevious = { [weak self] in
            self?.handlePageSwipe(isNext: false)
        }
        contentView.wantsLayer = true
        self.contentView = contentView

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
        if event.type == .scrollWheel,
           let scrollHandler = contentView as? PanelScrollHandling,
           scrollHandler.handlePanelScrollWheel(event) {
            return
        }

        super.sendEvent(event)
    }

    private func handleClipboardSwipe(isDownward: Bool) {
        guard state.isExpanded, state.contentVisible else { return }

        let isInverted = UserDefaults.standard.bool(
            forKey: BangBarSettings.Key.clipboardSwipeNavigationInverted
        )
        let shouldShowClipboard = isDownward != isInverted
        guard state.showsClipboardHistory != shouldShowClipboard else { return }

        TooltipManager.shared.hide()
        withAnimation(.easeOut(duration: 0.16)) {
            state.showsClipboardHistory = shouldShowClipboard
        }
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
        if clipboardHistory.isCollectingImages {
            state.showsClipboardHistory = true
            state.clipboardFilter = .images
        }
        let wasCompact = state.isCompact
        let wasNowPlayingCompact = state.compactContent == .nowPlaying
        let targetFrame = expandedFrame(on: screen, page: state.currentPage)

        if !isVisible {
            state.isExpanded = false
            state.isCompact = false
            state.contentVisible = false
            setFrame(targetFrame, display: true)
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
                })
            } else {
                self.state.artworkHeroProgress = nil
                self.state.isCompact = false
                self.state.isExpanded = true
                self.setFrame(targetFrame, display: true)
                self.state.contentVisible = true
            }
        }
    }

    private func cancelPendingTransition() {
        transitionID = UUID()
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

    func slideOut() {
        guard !isAnimatingFrame else { return }
        guard Date().timeIntervalSince(openedAt) > 0.5 else { return }
        wantsExpandedPanel = false
        cancelPendingTransition()
        let transition = transitionID
        TooltipManager.shared.hide()
        isHiding = true
        state.contentVisible = false
        state.showsClipboardHistory = false
        state.currentPage = 0

        if clipboardHistory.isCollectingImages || pomodoro.isRunning || nowPlaying.isCurrentlyPlaying {
            enterCompactMode()
            return
        }

        state.isExpanded = false
        state.isCompact = false
        state.artworkHeroProgress = nil
        if let screen = screen ?? NSScreen.main {
            animateFrame(to: compactFrame(on: screen), duration: 0.24)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.transitionID == transition else { return }
            if self.isHiding {
                self.orderOut(nil)
                self.isHiding = false
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }

    private func expandedFrame(on screen: NSScreen, page: Int = 0) -> NSRect {
        let width = PanelLayout.expandedWidth(forPage: page, on: screen)
        let height = PanelLayout.expandedHeight(on: screen)

        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func resizeExpandedPanelForCurrentSettings() {
        guard isVisible, state.isExpanded, !isAnimatingFrame, let screen = screen ?? NSScreen.main else { return }
        state.topSafeInset = PanelLayout.topSafeInset(on: screen)
        setFrame(expandedFrame(on: screen, page: state.currentPage), display: true)
    }

    private func compactFrame(on screen: NSScreen) -> NSRect {
        let width = compactWidth(on: screen)
        let height = compactHeight(on: screen)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func concealedCompactFrame(on screen: NSScreen) -> NSRect {
        let width = concealedCompactWidth(on: screen)
        let height = compactHeight(on: screen)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func compactHeight(on screen: NSScreen) -> CGFloat {
        if let topAreaHeight = screen.auxiliaryTopLeftArea?.height {
            return topAreaHeight
        }

        return NSStatusBar.system.thickness
    }

    private func compactWidth(on screen: NSScreen) -> CGFloat {
        let baseWidth: CGFloat
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = rightArea.minX - leftArea.maxX
            baseWidth = PanelLayout.compactWidth(for: notchWidth)
        } else {
            baseWidth = PanelLayout.compactMinimumWidth
        }
        return clipboardHistory.isCollectingImages ? baseWidth + 110 : baseWidth
    }

    private func concealedCompactWidth(on screen: NSScreen) -> CGFloat {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return 1
        }

        let notchWidth = rightArea.minX - leftArea.maxX
        return max(notchWidth - 8, 1)
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

        cancelPendingTransition()
        let transition = transitionID
        isHiding = false

        guard let screen = screen ?? NSScreen.main else { return }
        let targetFrame = compactFrame(on: screen)

        if !isVisible {
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
