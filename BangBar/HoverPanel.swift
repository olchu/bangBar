import AppKit
import Combine
import SwiftUI

class HoverPanel: NSPanel {
    var isHiding = false
    private var panelHeight: CGFloat = 155
    private var panelWidth: CGFloat = 620
    private var compactWidth: CGFloat = 300
    private let state = PanelState()
    private let nowPlaying = NowPlayingService()
    private var cancellables = Set<AnyCancellable>()
    private var hideWorkItem: DispatchWorkItem?
    private var frameAnimationTimer: Timer?
    private let hideDelay: TimeInterval = 0.45
    private var openedAt: Date = .distantPast

    var isCompactMode: Bool {
        state.isCompact
    }

    var isAnimatingFrame: Bool {
        frameAnimationTimer != nil
    }

    func containsCompactHoverPoint(_ screenPoint: NSPoint) -> Bool {
        guard state.isCompact else { return false }

        let localPoint = CGPoint(
            x: screenPoint.x - frame.minX,
            y: frame.maxY - screenPoint.y
        )
        let localBounds = CGRect(origin: .zero, size: frame.size)

        return NotchPanelShape()
            .path(in: localBounds)
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
        let initialRect = NSRect(
            x: screen.frame.midX - 620 / 2,
            y: screen.frame.maxY - 155,
            width: 620,
            height: 155
        )
        self.init(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func setupPanel() {
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let contentView = NSHostingView(rootView: PanelContentView(state: state, nowPlaying: nowPlaying))
        contentView.wantsLayer = true
        self.contentView = contentView

        nowPlaying.$info
            .combineLatest(nowPlaying.$isAvailable)
            .receive(on: RunLoop.main)
            .sink { [weak self] info, isAvailable in
                self?.syncCompactVisibility(isMusicPlaying: isAvailable && info.isPlaying)
            }
            .store(in: &cancellables)
    }

    // MARK: - Animation

    func slideIn() {
        guard !isAnimatingFrame else { return }
        isHiding = false
        openedAt = Date()
        hideWorkItem?.cancel()
        hideWorkItem = nil
        state.compactArtworkRevealAllowed = true
        state.compactIndicatorRevealAllowed = true

        guard let screen = NSScreen.main else { return }
        let wasCompact = state.isCompact
        let targetFrame = expandedFrame(on: screen)

        if !isVisible {
            state.isExpanded = false
            state.isCompact = false
            state.contentVisible = false
            setFrame(targetFrame, display: true)
            orderFront(nil)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if wasCompact {
                self.animateFrame(to: targetFrame, duration: 0.30) {
                    self.state.isCompact = false
                    self.state.isExpanded = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        self.state.contentVisible = true
                    }
                }
            } else {
                self.state.isCompact = false
                self.state.isExpanded = true
                self.setFrame(targetFrame, display: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    self.state.contentVisible = true
                }
            }
        }
    }

    func slideOut() {
        guard !isAnimatingFrame else { return }
        guard Date().timeIntervalSince(openedAt) > 0.5 else { return }
        isHiding = true

        if nowPlaying.isCurrentlyPlaying {
            enterCompactMode()
            return
        }

        state.isExpanded = false
        state.isCompact = false
        state.contentVisible = false
        if let screen = NSScreen.main {
            animateFrame(to: compactFrame(on: screen), duration: 0.24)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isHiding {
                self.orderOut(nil)
                self.isHiding = false
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: screen.frame.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )
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
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return compactWidth
        }

        let notchWidth = rightArea.minX - leftArea.maxX
        return min(max(notchWidth + 160, compactWidth), 390)
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
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isHiding = false

        guard let screen = NSScreen.main else { return }
        let targetFrame = compactFrame(on: screen)

        if !isVisible {
            frameAnimationTimer?.invalidate()
            frameAnimationTimer = nil
            updateStateWithoutAnimation {
                state.contentVisible = false
                state.isExpanded = false
                state.isCompact = false
                state.compactArtworkRevealAllowed = true
                state.compactIndicatorRevealAllowed = true
            }
            setFrame(targetFrame, display: false)
            contentView?.frame = NSRect(origin: .zero, size: targetFrame.size)
            contentView?.layoutSubtreeIfNeeded()
            displayIfNeeded()
            orderFront(nil)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setFrame(targetFrame, display: false)
                self.state.isCompact = true
            }
        } else {
            state.contentVisible = false
            state.isExpanded = false
            state.compactArtworkRevealAllowed = true
            state.compactIndicatorRevealAllowed = true
            state.isCompact = true
            animateFrame(to: targetFrame, duration: 0.24)
        }
    }

    private func syncCompactVisibility(isMusicPlaying: Bool) {
        if isMusicPlaying {
            if !isVisible || state.isCompact || isHiding {
                enterCompactMode()
            }
        } else if state.isCompact {
            exitCompactMode()
        }
    }

    private func exitCompactMode() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isHiding = true

        guard let screen = NSScreen.main else {
            orderOut(nil)
            isHiding = false
            updateStateWithoutAnimation {
                state.isCompact = false
                state.compactArtworkRevealAllowed = true
                state.compactIndicatorRevealAllowed = true
            }
            return
        }

        state.contentVisible = false
        state.isExpanded = false
        state.compactArtworkRevealAllowed = false
        state.compactIndicatorRevealAllowed = false
        state.isCompact = true

        let compactFrame = compactFrame(on: screen)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isHiding, !self.nowPlaying.isCurrentlyPlaying else { return }

            self.animateFrame(to: self.concealedCompactFrame(on: screen), duration: 0.24) { [weak self] in
                guard let self else { return }
                if self.isHiding, !self.nowPlaying.isCurrentlyPlaying {
                    self.orderOut(nil)
                    self.isHiding = false
                    self.updateStateWithoutAnimation {
                        self.state.isCompact = false
                        self.state.compactArtworkRevealAllowed = true
                        self.state.compactIndicatorRevealAllowed = true
                    }
                    self.setFrame(compactFrame, display: false)
                }
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func animateFrame(
        to frame: NSRect,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        frameAnimationTimer?.invalidate()

        let startFrame = self.frame
        let topY = frame.maxY
        let startTime = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let progress = min((CACurrentMediaTime() - startTime) / duration, 1)
            let easedProgress = 0.5 - 0.5 * cos(progress * .pi)

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
