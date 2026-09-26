import AppKit
import Combine
import SwiftUI

private final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class PlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class HoverTrackingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private var hoverTrackingArea: NSTrackingArea?
    var onHoverChange: ((Bool) -> Void)?

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

@MainActor
private final class StatusItemHoverMonitor: NSResponder {
    private weak var button: NSStatusBarButton?
    private let onHoverChange: (Bool) -> Void
    private var trackingArea: NSTrackingArea?

    init(button: NSStatusBarButton, onHoverChange: @escaping (Bool) -> Void) {
        self.button = button
        self.onHoverChange = onHoverChange
        super.init()
        installTrackingArea()
    }

    required init?(coder: NSCoder) { nil }

    func installTrackingArea() {
        guard let button else { return }
        if let trackingArea {
            button.removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
    }
}

@MainActor
final class PlayerWindowController: NSObject, NSWindowDelegate {
    static let shared = PlayerWindowController()

    private let expandedStatusItemWidth: CGFloat = 148
    private let compactStatusItemWidth: CGFloat = 38
    private let playerSize = NSSize(width: 326, height: 92)
    private let playerGap: CGFloat = 8

    private var statusItem: NSStatusItem?
    private var statusItemHoverMonitor: StatusItemHoverMonitor?
    private var statusHoverTimer: Timer?
    private var trackObservation: AnyCancellable?
    private var animationPreferenceObservation: AnyCancellable?
    private var statusArtwork: NSImage?
    private var fitCheckWorkItem: DispatchWorkItem?
    private var isStatusItemExpanded = true
    private var statusGlassView: NSView?
    private var statusGlassHighlightLayer: CAGradientLayer?
    private var statusArtworkLayer: CALayer?
    private var statusFallbackIconLayer: CATextLayer?
    private var statusTitleClipLayer: CALayer?
    private var statusTitleLayer: CATextLayer?
    private var statusTitleText = ""
    private var statusTitleTextWidth: CGFloat = 0
    private var marqueeAnimationSignature = ""
    private var equalizerBars: [CALayer] = []
    private var lastFitEvaluation = Date.distantPast
    private var playerPanel: PlayerPanel?
    private var collapseWorkItem: DispatchWorkItem?
    private var playbackHideWorkItem: DispatchWorkItem?
    private var statusItemHovered = false
    private var statusTrackingHovered = false
    private var statusPointerHovered = false
    private var playerHovered = false
    private var panelTransitionID = 0
    private var revealUntil = Date.distantPast

    func configure() {
        guard statusItem == nil else { return }

        configureStatusItem()
        configurePlayerPanel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: expandedStatusItemWidth)
        guard let button = item.button else { return }

        button.toolTip = "Nowlume"
        button.image = nil
        button.title = ""
        button.wantsLayer = true
        button.layer?.cornerCurve = .continuous
        button.layer?.cornerRadius = 11
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor(
            calibratedRed: 0.18,
            green: 0.26,
            blue: 0.40,
            alpha: 0.42
        ).cgColor
        button.layer?.borderWidth = 0.5
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        // Fire as soon as the pointer goes down. Waiting for mouse-up is fragile
        // here because the hover panel and the animated title are updating while
        // the status-bar button is tracking the click.
        button.sendAction(on: [.leftMouseDown])
        installStatusGlass(on: button)
        installStatusContent(on: button)

        statusItem = item
        statusItemHoverMonitor = StatusItemHoverMonitor(button: button) { [weak self] hovering in
            self?.setStatusItemHovered(hovering)
        }
        trackObservation = PlayerViewModel.shared.$track
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                self?.updateStatusItem(for: track)
                self?.updatePlaybackVisibility(for: track)
            }
        updateStatusItem(for: PlayerViewModel.shared.track)
        animationPreferenceObservation = Preferences.shared.$reduceAnimations
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.marqueeAnimationSignature = ""
                self?.updateStatusMarquee()
                self?.updateEqualizer()
            }
        updateStatusActivity()
        scheduleFitCheck()
    }

    private func updateStatusActivity() {
        let visible = statusItem?.isVisible == true
        if visible && statusHoverTimer == nil {
            // Native tracking handles normal hover. Poll only as a fallback for
            // events consumed by the status bar; animation needs no CPU timer.
            let timer = Timer(timeInterval: 0.2, target: self,
                              selector: #selector(pollStatusItemHover),
                              userInfo: nil, repeats: true)
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            statusHoverTimer = timer
        } else if !visible {
            statusHoverTimer?.invalidate()
            statusHoverTimer = nil
        }
        updateEqualizer()
        updateStatusMarquee()
    }

    @objc private func pollStatusItemHover() {
        updateStatusHoverFromPointer()
        if (statusItemHovered || playerHovered || Date() < revealUntil),
           playerPanel?.isVisible != true {
            showPlayer(animated: true)
        }
        let now = Date()
        if now.timeIntervalSince(lastFitEvaluation) >= 0.75 {
            lastFitEvaluation = now
            updateAdaptiveStatusWidth()
        }
    }

    private func updateStatusHoverFromPointer() {
        guard let button = statusItem?.button,
              let window = button.window,
              window.isVisible else {
            setStatusPointerHovered(false)
            return
        }

        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(buttonFrame) }
        setStatusPointerHovered(onScreen && buttonFrame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation))
    }

    private func updateStatusItem(for track: Track?) {
        guard statusItem?.button != nil else { return }

        if track?.artwork !== statusArtwork {
            statusArtwork = track?.artwork
            if let artwork = track?.artwork {
                var proposedRect = NSRect(x: 0, y: 0, width: 24, height: 24)
                statusArtworkLayer?.contents = artwork.cgImage(
                    forProposedRect: &proposedRect,
                    context: nil,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
                statusArtworkLayer?.backgroundColor = NSColor.clear.cgColor
                statusFallbackIconLayer?.isHidden = true
            } else {
                statusArtworkLayer?.contents = nil
                statusArtworkLayer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
                statusFallbackIconLayer?.isHidden = false
            }
        }
        statusArtworkLayer?.contentsGravity = .resizeAspectFill

        let title = (track?.title ?? "Nowlume").trimmingCharacters(in: .whitespacesAndNewlines)
        if title != statusTitleText {
            statusTitleText = title
            marqueeAnimationSignature = ""
            let attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                    .foregroundColor: NSColor.white
                ]
            )
            statusTitleTextWidth = ceil(attributedTitle.size().width) + 2
            statusTitleLayer?.string = attributedTitle
        }
        updateStatusContentLayout()
        updateStatusMarquee()
        updateEqualizer()
    }

    private func installStatusGlass(on button: NSStatusBarButton) {
        let blur = PassthroughVisualEffectView(frame: button.bounds)
        blur.material = .menu
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 11
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        let glassView: NSView = blur

        glassView.autoresizingMask = [.width, .height]
        glassView.wantsLayer = true
        glassView.layer?.zPosition = -1
        button.addSubview(glassView, positioned: .below, relativeTo: nil)
        statusGlassView = glassView

        guard let rootLayer = button.layer else { return }
        let highlight = CAGradientLayer()
        highlight.colors = [
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.white.withAlphaComponent(0.025).cgColor,
            NSColor.clear.cgColor
        ]
        highlight.locations = [0, 0.42, 1]
        highlight.startPoint = CGPoint(x: 0.05, y: 1)
        highlight.endPoint = CGPoint(x: 0.95, y: 0)
        highlight.cornerRadius = 11
        highlight.zPosition = 0
        rootLayer.addSublayer(highlight)
        statusGlassHighlightLayer = highlight
    }

    private func installStatusContent(on button: NSStatusBarButton) {
        guard let rootLayer = button.layer else { return }

        let artworkLayer = CALayer()
        artworkLayer.masksToBounds = true
        artworkLayer.zPosition = 1
        rootLayer.addSublayer(artworkLayer)
        statusArtworkLayer = artworkLayer

        let fallbackIconLayer = CATextLayer()
        fallbackIconLayer.string = NSAttributedString(
            string: "♪",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88)
            ]
        )
        fallbackIconLayer.contentsScale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        fallbackIconLayer.alignmentMode = .center
        fallbackIconLayer.zPosition = 2
        rootLayer.addSublayer(fallbackIconLayer)
        statusFallbackIconLayer = fallbackIconLayer

        let titleClipLayer = CALayer()
        titleClipLayer.masksToBounds = true
        titleClipLayer.zPosition = 1
        rootLayer.addSublayer(titleClipLayer)
        statusTitleClipLayer = titleClipLayer

        let titleLayer = CATextLayer()
        titleLayer.contentsScale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.alignmentMode = .left
        titleLayer.truncationMode = .none
        titleLayer.isWrapped = false
        titleLayer.zPosition = 1
        titleClipLayer.addSublayer(titleLayer)
        statusTitleLayer = titleLayer

        equalizerBars = (0..<3).map { _ in
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = 1
            bar.zPosition = 2
            rootLayer.addSublayer(bar)
            return bar
        }
        updateStatusContentLayout()
        updateEqualizer()
    }

    private func updateStatusContentLayout() {
        guard let button = statusItem?.button else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let height = button.bounds.height
        statusGlassView?.frame = button.bounds
        statusGlassHighlightLayer?.frame = button.bounds
        statusArtworkLayer?.frame = NSRect(x: 0, y: 0, width: height, height: height)
        statusArtworkLayer?.cornerRadius = 0
        statusFallbackIconLayer?.frame = NSRect(x: 0, y: max(1, button.bounds.midY - 9), width: height, height: 18)
        let titleFrame = NSRect(
            x: height + 7,
            // CATextLayer's font metrics make the glyphs look slightly high even
            // when its frame is mathematically centered. One point of optical
            // compensation aligns the title with the artwork/equalizer.
            y: max(1, button.bounds.midY - 7),
            width: max(0, button.bounds.width - height - 31),
            height: 16
        )
        statusTitleClipLayer?.frame = titleFrame
        statusTitleClipLayer?.isHidden = !isStatusItemExpanded
        statusTitleLayer?.frame = NSRect(
            x: 0,
            y: 0,
            width: max(titleFrame.width, statusTitleTextWidth),
            height: titleFrame.height
        )
        CATransaction.commit()
    }

    private func updateStatusMarquee() {
        guard let clipLayer = statusTitleClipLayer,
              let titleLayer = statusTitleLayer,
              isStatusItemExpanded,
              statusItem?.isVisible == true,
              !Preferences.shared.reduceAnimations else {
            statusTitleLayer?.removeAnimation(forKey: "smoothMarquee")
            marqueeAnimationSignature = ""
            return
        }

        let overflow = max(0, statusTitleTextWidth - clipLayer.bounds.width)
        let startPause: TimeInterval = 1.25
        let endPause: TimeInterval = 0.8
        let speed: CGFloat = 22
        let scrollDuration = overflow > 0 ? TimeInterval(overflow / speed) : 0
        let cycleDuration = startPause + scrollDuration + endPause
        let signature = "\(statusTitleText)|\(clipLayer.bounds.width)|\(overflow)|\(isStatusItemExpanded)"
        guard signature != marqueeAnimationSignature else { return }
        marqueeAnimationSignature = signature

        titleLayer.removeAnimation(forKey: "smoothMarquee")
        guard overflow > 0, cycleDuration > 0 else { return }

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -overflow, -overflow]
        animation.keyTimes = [
            0,
            NSNumber(value: startPause / cycleDuration),
            NSNumber(value: (startPause + scrollDuration) / cycleDuration),
            1
        ]
        let linear = CAMediaTimingFunction(name: .linear)
        animation.timingFunctions = [linear, linear, linear]
        animation.duration = cycleDuration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        titleLayer.add(animation, forKey: "smoothMarquee")
    }

    private func updateEqualizer() {
        guard let button = statusItem?.button, equalizerBars.count == 3 else { return }
        let isPlaying = PlayerViewModel.shared.track?.isPlaying == true
        let animates = isPlaying && statusItem?.isVisible == true && !Preferences.shared.reduceAnimations

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let startX = button.bounds.maxX - 15
        for (index, bar) in equalizerBars.enumerated() {
            bar.frame = NSRect(x: startX + CGFloat(index) * 4,
                               y: button.bounds.midY - 5.5, width: 2, height: 11)
            bar.opacity = isPlaying ? 0.92 : 0.42
            bar.transform = CATransform3DMakeScale(1, 4.0 / 11.0, 1)
            if animates {
                guard bar.animation(forKey: "equalizer") == nil else { continue }
                let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
                animation.values = [4.0 / 11.0, 1.0, 6.0 / 11.0, 9.0 / 11.0, 4.0 / 11.0]
                animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                animation.duration = 0.8 + Double(index) * 0.17
                animation.timeOffset = Double(index) * 0.23
                animation.calculationMode = .cubic
                animation.repeatCount = .infinity
                bar.add(animation, forKey: "equalizer")
            } else {
                bar.removeAnimation(forKey: "equalizer")
            }
        }
        CATransaction.commit()
    }

    private func setStatusItemExpanded(_ expanded: Bool) {
        guard isStatusItemExpanded != expanded, let statusItem else { return }
        isStatusItemExpanded = expanded
        statusItem.length = expanded ? expandedStatusItemWidth : compactStatusItemWidth
        updateStatusItem(for: PlayerViewModel.shared.track)
        statusItemHoverMonitor?.installTrackingArea()
    }

    private func scheduleFitCheck() {
        fitCheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.collapseIfStatusItemDoesNotFit()
        }
        fitCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func collapseIfStatusItemDoesNotFit() {
        guard isStatusItemExpanded,
              let button = statusItem?.button else { return }

        let windowIsUsable = button.window?.isVisible == true
            && button.window?.screen != nil
            && button.window?.frame.intersects(button.window?.screen?.frame ?? .zero) == true
        if !windowIsUsable {
            setStatusItemExpanded(false)
        }
    }

    private func updateAdaptiveStatusWidth() {
        guard let button = statusItem?.button,
              let window = button.window,
              let screen = window.screen else { return }

        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        if let rightSafeArea = screen.auxiliaryTopRightArea, !rightSafeArea.isEmpty {
            // The right edge stays anchored beside the following menu-bar item.
            // This lets us know whether the wide version would cross under the
            // camera before asking macOS to expand it.
            let availableWidth = buttonFrame.maxX - rightSafeArea.minX - 5
            setStatusItemExpanded(availableWidth >= expandedStatusItemWidth)
        } else if !window.isVisible || !buttonFrame.intersects(screen.frame) {
            setStatusItemExpanded(false)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        reveal()
    }

    private func configurePlayerPanel() {
        let content = PlayerView()
            .environmentObject(PlayerViewModel.shared)
            .environmentObject(Preferences.shared)
            .frame(width: playerSize.width, height: playerSize.height)
        let trackingView = HoverTrackingView(rootView: content)
        trackingView.layer?.cornerRadius = 20
        trackingView.onHoverChange = { [weak self] hovering in
            self?.setPlayerHovered(hovering)
        }

        let panel = PlayerPanel(
            contentRect: NSRect(origin: .zero, size: playerSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = trackingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.delegate = self
        panel.alphaValue = 0
        playerPanel = panel
    }

    func show() {
        configure()
        updatePlaybackVisibility(for: PlayerViewModel.shared.track, immediately: true)
    }

    func reveal() {
        show()
        revealUntil = Date().addingTimeInterval(2.2)
        showPlayer(animated: true)
        scheduleCollapse(after: 2.2)
    }

    func hide() {
        collapseWorkItem?.cancel()
        playbackHideWorkItem?.cancel()
        statusItem?.isVisible = false
        updateStatusActivity()
        hidePlayer(animated: false)
    }

    func toggleVisibility() {
        guard let statusItem else { return }
        statusItem.isVisible ? hide() : show()
    }

    private func updatePlaybackVisibility(for track: Track?, immediately: Bool = false) {
        playbackHideWorkItem?.cancel()

        if track?.isPlaying == true {
            guard statusItem?.isVisible != true else { return }
            statusItem?.isVisible = true
            updateStatusActivity()
            DispatchQueue.main.async { [weak self] in
                self?.updateStatusContentLayout()
                self?.statusItemHoverMonitor?.installTrackingArea()
                self?.updateAdaptiveStatusWidth()
            }
            return
        }

        let hideStoppedPlayback = { [weak self] in
            guard let self, PlayerViewModel.shared.track?.isPlaying != true else { return }
            self.statusItemHovered = false
            self.statusTrackingHovered = false
            self.statusPointerHovered = false
            self.playerHovered = false
            self.statusItem?.isVisible = false
            self.updateStatusActivity()
            self.hidePlayer(animated: true)
        }

        if immediately {
            hideStoppedPlayback()
        } else {
            let workItem = DispatchWorkItem(block: hideStoppedPlayback)
            playbackHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
        }
    }

    private func setStatusItemHovered(_ hovering: Bool) {
        statusTrackingHovered = hovering
        updateCombinedStatusHover()
    }

    private func setStatusPointerHovered(_ hovering: Bool) {
        statusPointerHovered = hovering
        updateCombinedStatusHover()
    }

    private func updateCombinedStatusHover() {
        let hovering = statusTrackingHovered || statusPointerHovered
        guard hovering != statusItemHovered else { return }
        statusItemHovered = hovering
        hoverStateDidChange()
    }

    private func setPlayerHovered(_ hovering: Bool) {
        playerHovered = hovering
        hoverStateDidChange()
    }

    private func hoverStateDidChange() {
        collapseWorkItem?.cancel()
        if statusItemHovered || playerHovered {
            showPlayer(animated: true)
        } else {
            scheduleCollapse(after: 0.55)
        }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.statusItemHovered, !self.playerHovered else { return }
            self.hidePlayer(animated: true)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func showPlayer(animated: Bool) {
        guard let playerPanel,
              statusItem?.isVisible == true,
              let finalFrame = playerFrame() else { return }

        panelTransitionID += 1
        PlayerViewModel.shared.isPlayerVisible = true

        if playerPanel.isVisible {
            // A visible panel may still belong to the previous fullscreen Space.
            playerPanel.setFrame(finalFrame, display: true)
            playerPanel.orderFrontRegardless()
            playerPanel.alphaValue = 1
            return
        }

        guard animated else {
            playerPanel.alphaValue = 1
            playerPanel.setFrame(finalFrame, display: true)
            playerPanel.orderFrontRegardless()
            return
        }

        var startFrame = finalFrame
        startFrame.origin.y += 6
        playerPanel.alphaValue = 0
        playerPanel.setFrame(startFrame, display: true)
        playerPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            playerPanel.animator().alphaValue = 1
            playerPanel.animator().setFrame(finalFrame, display: true)
        }
    }

    private func hidePlayer(animated: Bool) {
        revealUntil = .distantPast
        panelTransitionID += 1
        let transitionID = panelTransitionID
        PlayerViewModel.shared.isPlayerVisible = false
        guard let playerPanel, playerPanel.isVisible else { return }
        guard animated else {
            playerPanel.alphaValue = 0
            playerPanel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            playerPanel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak playerPanel] in
            DispatchQueue.main.async {
                guard let self, self.panelTransitionID == transitionID else { return }
                playerPanel?.orderOut(nil)
            }
        }
    }

    private func playerFrame() -> NSRect? {
        guard let button = statusItem?.button,
              let window = button.window,
              window.isVisible else { return nil }

        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(buttonFrame) }) else {
            return nil
        }
        let x = min(
            max(screen.frame.minX + 10, buttonFrame.maxX - playerSize.width),
            screen.frame.maxX - playerSize.width - 10
        )
        return NSRect(
            x: x,
            y: buttonFrame.minY - playerGap - playerSize.height,
            width: playerSize.width,
            height: playerSize.height
        )
    }

    @objc private func screenConfigurationDidChange() {
        updateAdaptiveStatusWidth()
        if let frame = playerFrame() {
            playerPanel?.setFrame(frame, display: true)
        }
    }

    @objc private func frontmostApplicationDidChange() {
        updateAdaptiveStatusWidth()
    }

    @objc private func activeSpaceDidChange() {
        statusItemHovered = false
        statusTrackingHovered = false
        statusPointerHovered = false
        playerHovered = false
        hidePlayer(animated: false)
        // The status item's window can move after the Space notification arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.statusItemHoverMonitor?.installTrackingArea()
            self?.updateStatusHoverFromPointer()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePlayer(animated: false)
        return false
    }
}
