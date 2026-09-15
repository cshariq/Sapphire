//
//  NotchHoverMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import Cocoa

@MainActor
struct NotchHoverMonitorHandlers {
    var onPointerEvent: () -> Void
    var onMouseDrag: (_ isInside: Bool, _ screenLocation: NSPoint) -> Void
    var onMouseDragEnded: (_ screenLocation: NSPoint) -> Void
    var onFileDrag: (_ isTargeted: Bool, _ screenLocation: NSPoint) -> Void
    var onFileDragEnded: (_ screenLocation: NSPoint, _ dropWasAccepted: Bool) -> Void
    var onFileDrop: (_ urls: [URL], _ screenLocation: NSPoint) -> Bool
}

// MARK: - Tracking View

final class HoverTrackingView: NSView {
    var onPointerEvent: ((_ isInside: Bool, _ event: NSEvent) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { onPointerEvent?(true, event) }
    override func mouseExited(with event: NSEvent) { onPointerEvent?(false, event) }
}

// MARK: - Probe Window

final class HoverProbeWindow: NSPanel, NSDraggingDestination {
    var onFileDragBegan: ((NSPoint) -> Void)?
    var onFileDragMoved: ((NSPoint) -> Void)?
    var onFileDragExited: ((NSPoint) -> Void)?
    var onFileDragEnded: ((NSPoint, Bool) -> Void)?
    var onFileDrop: (([URL], NSPoint) -> Bool)?

    private(set) var isFileDragSessionActive = false
    private(set) var isArmedForMouseSequence = false
    private var didAcceptFileDropInCurrentSession = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(level: NSWindow.Level, collectionBehavior: NSWindow.CollectionBehavior) {
        self.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        self.level = level
        self.collectionBehavior = collectionBehavior
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        sharingType = .none
    }

    func enableFileDropDestination() {
        registerForDraggedTypes([.fileURL, FileDragPasteboard.legacyFilenamesType])
    }

    func disableFileDropDestination() {
        unregisterDraggedTypes()
        isFileDragSessionActive = false
        didAcceptFileDropInCurrentSession = false
        onFileDragBegan = nil
        onFileDragMoved = nil
        onFileDragExited = nil
        onFileDragEnded = nil
        onFileDrop = nil
    }

    func setArmedForMouseSequence(_ isArmed: Bool) {
        isArmedForMouseSequence = isArmed
        ignoresMouseEvents = !isArmed && !isFileDragSessionActive
    }

    // MARK: NSDraggingDestination

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = acceptedOperation(for: sender)
        guard !operation.isEmpty else { return [] }
        isFileDragSessionActive = true
        didAcceptFileDropInCurrentSession = false
        ignoresMouseEvents = false
        let location = screenLocation(for: sender)
        onFileDragBegan?(location)
        return operation
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = acceptedOperation(for: sender)
        guard !operation.isEmpty else { return [] }
        onFileDragMoved?(screenLocation(for: sender))
        return operation
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        onFileDragExited?(screenLocation(for: sender))
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !acceptedOperation(for: sender).isEmpty
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let wasAccepted = onFileDrop?(urls, screenLocation(for: sender)) ?? false
        didAcceptFileDropInCurrentSession = wasAccepted
        return wasAccepted
    }

    func draggingEnded(_ sender: NSDraggingInfo) {
        finishFileDrag(at: screenLocation(for: sender))
    }

    func concludeDragOperation(_ sender: NSDraggingInfo?) {
        finishFileDrag(at: screenLocation(for: sender))
    }

    private func canAcceptFiles(from sender: NSDraggingInfo) -> Bool {
        guard onFileDrop != nil else { return false }
        return FileDragPasteboard.containsFiles(sender.draggingPasteboard)
    }

    private func acceptedOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptFiles(from: sender) else { return [] }
        let sourceOperations = sender.draggingSourceOperationMask
        if sourceOperations.contains(.copy) { return .copy }
        if sourceOperations.contains(.generic) { return .generic }
        return []
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        FileDragPasteboard.fileURLs(from: pasteboard)
    }

    private func screenLocation(for sender: NSDraggingInfo?) -> NSPoint {
        guard let sender else { return NSEvent.mouseLocation }
        return convertPoint(toScreen: sender.draggingLocation)
    }

    private func finishFileDrag(at location: NSPoint) {
        guard isFileDragSessionActive else { return }
        let dropWasAccepted = didAcceptFileDropInCurrentSession
        isFileDragSessionActive = false
        didAcceptFileDropInCurrentSession = false
        ignoresMouseEvents = !isArmedForMouseSequence
        onFileDragEnded?(location, dropWasAccepted)
    }
}

// MARK: - Monitor

@MainActor
final class NotchHoverMonitor {
    private weak var notchWindow: NSWindow?
    private var probeWindow: HoverProbeWindow?
    private var tracker: HoverTrackingView?
    private var handlers: NotchHoverMonitorHandlers?

    private var currentRect: CGRect = .null
    private var requestedRect: CGRect = .null
    private var pendingRect: CGRect = .null
    private var settleTask: Task<Void, Never>?
    private var isParked = true
    private var pointerIsInside = false
    private var stuckHoverWatchdog: Timer?
    private var dragPollingTimer: Timer?
    private var deferredDisarmTask: Task<Void, Never>?
    private var pendingPlainDragEndLocation: NSPoint?
    private var pendingProactiveFileDragEndLocation: NSPoint?
    private var localMouseMonitor: Any?
    private var mouseDownToken: UUID?
    private var mouseUpToken: UUID?
    private var mouseDownLocation: NSPoint?
    private var lastIdleDragPasteboardChangeCount = 0
    private var dragPasteboardChangeCountBeforeMouseSequence: Int?
    private var mouseSequenceGeneration: UInt64 = 0
    private var activeMouseSequenceGeneration: UInt64?
    private var hasObservedMouseDrag = false
    private var hasEnteredDuringMouseDrag = false
    private var didObserveFileDragInMouseSequence = false
    private var didTargetFileDragInMouseSequence = false
    private var isProactiveFileDragTargeted = false
    private var isUsingDragEnvelope = false

    private static let resizeThreshold: CGFloat = 6
    private static let mouseDragThresholdSquared: CGFloat = 9
    private static let dragEnvelopeSize = CGSize(width: 640, height: 240)
    private static let lateNativeFileDragGrace: Duration = .milliseconds(100)

    private static let stuckHoverWatchdogInterval: TimeInterval = 0.2

    var isRunning: Bool { notchWindow != nil }

    // MARK: Lifecycle

    func start(window: NSWindow, handlers: NotchHoverMonitorHandlers) {
        if notchWindow === window, probeWindow != nil {
            self.handlers = handlers
            return
        }
        stop()

        notchWindow = window
        self.handlers = handlers
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount

        let probe = HoverProbeWindow(level: window.level, collectionBehavior: window.collectionBehavior)
        let tracker = HoverTrackingView(frame: .zero)
        tracker.autoresizingMask = [.width, .height]
        tracker.onPointerEvent = { [weak self] isInside, event in
            self?.handleProbeBoundary(isInside: isInside, event: event)
        }
        probe.contentView = tracker

        probe.onFileDragBegan = { [weak self] location in
            self?.handleFileDragBegan(at: location)
        }
        probe.onFileDragMoved = { [weak self] location in
            self?.handlers?.onFileDrag(true, location)
        }
        probe.onFileDragExited = { [weak self] location in
            self?.handlers?.onFileDrag(false, location)
        }
        probe.onFileDragEnded = { [weak self] location, dropWasAccepted in
            self?.handleFileDragEnded(at: location, dropWasAccepted: dropWasAccepted)
        }
        probe.onFileDrop = { [weak self] urls, location in
            self?.handlers?.onFileDrop(urls, location) ?? false
        }
        probe.enableFileDropDestination()

        self.tracker = tracker
        self.probeWindow = probe

        (NSApp.delegate as? AppDelegate)?.attachAuxiliaryNotchWindow(probe)
        window.addChildWindow(probe, ordered: .above)

        mouseDownToken = EventMonitorHub.shared.register(for: .leftMouseDown) { [weak self] event in
            guard let self else { return }
            self.armForPotentialMouseDrag(at: self.screenLocation(for: event))
        }
        mouseUpToken = EventMonitorHub.shared.register(for: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            self.handleMouseUp(at: self.screenLocation(for: event))
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let location = self.screenLocation(for: event)
                switch event.type {
                case .leftMouseDown:
                    self.armForPotentialMouseDrag(at: location)
                case .leftMouseDragged:
                    self.handleMouseDragged(at: location)
                case .leftMouseUp:
                    self.handleMouseUp(at: location)
                default:
                    break
                }
            }
            return event
        }
    }

    func stop() {
        stuckHoverWatchdog?.invalidate()
        stuckHoverWatchdog = nil
        stopDragPolling()
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        settleTask?.cancel()
        settleTask = nil

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let token = mouseDownToken {
            EventMonitorHub.shared.unregister(token: token, for: .leftMouseDown)
            mouseDownToken = nil
        }
        if let token = mouseUpToken {
            EventMonitorHub.shared.unregister(token: token, for: .leftMouseUp)
            mouseUpToken = nil
        }
        mouseDownLocation = nil
        activeMouseSequenceGeneration = nil
        dragPasteboardChangeCountBeforeMouseSequence = nil
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        hasObservedMouseDrag = false
        hasEnteredDuringMouseDrag = false
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        isProactiveFileDragTargeted = false

        tracker?.onPointerEvent = nil
        tracker = nil

        if let probeWindow {
            probeWindow.disableFileDropDestination()
            notchWindow?.removeChildWindow(probeWindow)
            (NSApp.delegate as? AppDelegate)?.detachAuxiliaryNotchWindow(probeWindow)
            probeWindow.orderOut(nil)
            probeWindow.contentView = nil
            probeWindow.close()
        }
        probeWindow = nil

        notchWindow = nil
        handlers = nil
        currentRect = .null
        requestedRect = .null
        isParked = true
        pointerIsInside = false
        isUsingDragEnvelope = false
    }

    // MARK: Geometry

    func update(hoverRect rect: CGRect, pointerIsInside: Bool) {
        guard let window = notchWindow, let probeWindow else { return }

        self.pointerIsInside = pointerIsInside
        syncStuckHoverWatchdog()

        guard !rect.isNull, !rect.isEmpty else {
            requestedRect = .null
            park()
            return
        }
        requestedRect = rect
        let effectiveRect = dragEnvelopeRect(for: rect)

        if probeWindow.isArmedForMouseSequence || probeWindow.isFileDragSessionActive {
            if !effectiveRect.equalTo(currentRect) {
                applyRect(effectiveRect, to: probeWindow, in: window)
            }
        } else if movedMeaningfully(from: currentRect, to: effectiveRect) {
            applyRect(effectiveRect, to: probeWindow, in: window)
        } else if !effectiveRect.equalTo(currentRect) {
            scheduleSettle(effectiveRect)
        }

        if isParked {
            isParked = false
            probeWindow.order(.above, relativeTo: window.windowNumber)
        }
    }

    private func applyRect(_ rect: CGRect, to probeWindow: HoverProbeWindow, in window: NSWindow) {
        settleTask?.cancel()
        settleTask = nil
        pendingRect = .null
        currentRect = rect
        let screenRect = window.convertToScreen(rect)
        probeWindow.setFrame(screenRect, display: false)
        notifyIfContainmentDisagrees(with: screenRect)
        refreshMouseDragContainment(at: NSEvent.mouseLocation)
    }

    private func notifyIfContainmentDisagrees(with screenRect: CGRect) {
        let containsPointer = screenRect.contains(NSEvent.mouseLocation)
        guard containsPointer != pointerIsInside else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleProbePointerSample()
        }
    }

    private func scheduleSettle(_ rect: CGRect) {
        pendingRect = rect
        guard settleTask == nil else { return }
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.settleTask = nil
            let pending = self.pendingRect
            self.pendingRect = .null
            guard !pending.isNull, !pending.equalTo(self.currentRect) else { return }
            guard let probeWindow = self.probeWindow, let window = self.notchWindow else { return }
            self.currentRect = pending
            let screenRect = window.convertToScreen(pending)
            probeWindow.setFrame(screenRect, display: false)
            self.notifyIfContainmentDisagrees(with: screenRect)
            self.refreshMouseDragContainment(at: NSEvent.mouseLocation)
        }
    }

    private func park() {
        settleTask?.cancel()
        settleTask = nil
        pendingRect = .null
        guard !isParked else { return }
        isParked = true
        currentRect = .null
        probeWindow?.orderOut(nil)
    }

    private func movedMeaningfully(from old: CGRect, to new: CGRect) -> Bool {
        if old.isNull { return true }
        let threshold = Self.resizeThreshold
        return abs(new.minX - old.minX) > threshold
            || abs(new.minY - old.minY) > threshold
            || abs(new.width - old.width) > threshold
            || abs(new.height - old.height) > threshold
    }

    private func dragEnvelopeRect(for rect: CGRect) -> CGRect {
        guard isUsingDragEnvelope else { return rect }
        let width = max(rect.width, Self.dragEnvelopeSize.width)
        let height = max(rect.height, Self.dragEnvelopeSize.height)
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.maxY - height,
            width: width,
            height: height
        )
    }

    private func activateDragEnvelope() {
        guard !isUsingDragEnvelope else { return }
        isUsingDragEnvelope = true
        applyRequestedRectForCurrentEnvelope()
    }

    private func deactivateDragEnvelope() {
        guard isUsingDragEnvelope else { return }
        isUsingDragEnvelope = false
        applyRequestedRectForCurrentEnvelope()
    }

    private func applyRequestedRectForCurrentEnvelope() {
        guard !requestedRect.isNull,
              !requestedRect.isEmpty,
              let probeWindow,
              let notchWindow else { return }
        let rect = dragEnvelopeRect(for: requestedRect)
        guard !rect.equalTo(currentRect) else { return }
        applyRect(rect, to: probeWindow, in: notchWindow)
    }

    private func syncStuckHoverWatchdog() {
        if pointerIsInside {
            guard stuckHoverWatchdog == nil else { return }
            let timer = Timer(
                timeInterval: Self.stuckHoverWatchdogInterval,
                repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleProbePointerSample() }
            }
            timer.tolerance = Self.stuckHoverWatchdogInterval * 0.25
            RunLoop.main.add(timer, forMode: .common)
            stuckHoverWatchdog = timer
        } else {
            stuckHoverWatchdog?.invalidate()
            stuckHoverWatchdog = nil
        }
    }

    // MARK: Drag ownership

    private func handleProbeBoundary(isInside: Bool, event: NSEvent) {
        if NSEvent.pressedMouseButtons & 1 != 0 {
            handleMouseDragged(
                at: screenLocation(for: event),
                knownContainment: isInside
            )
        } else {
            lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        }
        handlers?.onPointerEvent()
    }

    private func handleProbePointerSample() {
        if NSEvent.pressedMouseButtons & 1 != 0 {
            armForPotentialMouseDrag(at: NSEvent.mouseLocation)
        } else {
            lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        }
        handlers?.onPointerEvent()
    }

    private func armForPotentialMouseDrag(at location: NSPoint) {
        guard NSEvent.pressedMouseButtons & 1 != 0,
              let probeWindow else { return }

        finishDeferredMouseSequenceBeforeNewPress(in: probeWindow)
        guard !probeWindow.isFileDragSessionActive,
              mouseDownLocation == nil else { return }

        beginMouseSequence(at: location, in: probeWindow)
    }

    private func beginMouseSequence(at location: NSPoint, in probeWindow: HoverProbeWindow) {
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        mouseSequenceGeneration &+= 1
        activeMouseSequenceGeneration = mouseSequenceGeneration
        mouseDownLocation = location
        dragPasteboardChangeCountBeforeMouseSequence = lastIdleDragPasteboardChangeCount
        hasObservedMouseDrag = false
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        isProactiveFileDragTargeted = false
        probeWindow.setArmedForMouseSequence(true)
        startDragPolling()
    }

    private func finishDeferredMouseSequenceBeforeNewPress(in probeWindow: HoverProbeWindow) {
        guard mouseDownLocation == nil,
              activeMouseSequenceGeneration != nil,
              !probeWindow.isFileDragSessionActive else { return }

        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        if let location = pendingPlainDragEndLocation,
           !didObserveFileDragInMouseSequence {
            handlers?.onMouseDrag(false, location)
            handlers?.onMouseDragEnded(location)
        }
        if let location = pendingProactiveFileDragEndLocation {
            isProactiveFileDragTargeted = false
            handlers?.onFileDrag(false, location)
            handlers?.onFileDragEnded(location, false)
        }
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        activeMouseSequenceGeneration = nil
        dragPasteboardChangeCountBeforeMouseSequence = nil
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        deactivateDragEnvelope()
        probeWindow.setArmedForMouseSequence(false)
    }

    private func handleMouseDragged(
        at location: NSPoint,
        knownContainment: Bool? = nil
    ) {
        guard NSEvent.pressedMouseButtons & 1 != 0,
              let probeWindow else { return }
        if mouseDownLocation == nil {
            finishDeferredMouseSequenceBeforeNewPress(in: probeWindow)
        }
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        if activeMouseSequenceGeneration == nil || mouseDownLocation == nil {
            beginMouseSequence(at: location, in: probeWindow)
        }
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        mouseDownLocation = mouseDownLocation ?? location
        hasObservedMouseDrag = true
        probeWindow.setArmedForMouseSequence(true)
        startDragPolling()

        guard !probeWindow.isFileDragSessionActive else { return }
        if let isInside = knownContainment {
            publishMouseDragContainment(isInside, at: location)
            return
        }
        refreshMouseDragContainment(at: location)
    }

    private func refreshMouseDragContainment(at location: NSPoint) {
        guard let probeWindow,
              probeWindow.isArmedForMouseSequence,
              hasObservedMouseDrag,
              NSEvent.pressedMouseButtons & 1 != 0,
              !probeWindow.isFileDragSessionActive else { return }

        let isInside = probeWindow.isVisible && probeWindow.frame.contains(location)
        publishMouseDragContainment(isInside, at: location)
    }

    private func publishMouseDragContainment(_ isInside: Bool, at location: NSPoint) {
        let dragPasteboard = NSPasteboard(name: .drag)
        if let baseline = dragPasteboardChangeCountBeforeMouseSequence,
           FileDragPasteboard.containsFiles(dragPasteboard, newerThan: baseline) {
            didObserveFileDragInMouseSequence = true
            hasEnteredDuringMouseDrag = false
            if isInside {
                didTargetFileDragInMouseSequence = true
                activateDragEnvelope()
            }
            if isInside || isProactiveFileDragTargeted {
                handlers?.onFileDrag(isInside, location)
            }
            isProactiveFileDragTargeted = isInside
            return
        }

        if isProactiveFileDragTargeted {
            isProactiveFileDragTargeted = false
            handlers?.onFileDrag(false, location)
        }
        if isInside {
            hasEnteredDuringMouseDrag = true
            activateDragEnvelope()
        }
        handlers?.onMouseDrag(isInside, location)
    }

    private func handleMouseUp(at location: NSPoint) {
        guard let probeWindow,
              let sequenceGeneration = activeMouseSequenceGeneration else { return }
        stopDragPolling()

        if !didObserveFileDragInMouseSequence,
           let baseline = dragPasteboardChangeCountBeforeMouseSequence,
           probeWindow.isVisible,
           probeWindow.frame.contains(location),
           FileDragPasteboard.containsFiles(NSPasteboard(name: .drag), newerThan: baseline) {
            didObserveFileDragInMouseSequence = true
            didTargetFileDragInMouseSequence = true
            isProactiveFileDragTargeted = true
            handlers?.onMouseDrag(false, location)
            handlers?.onFileDrag(true, location)
        }

        let wasObservedDragReleasedInsideProbe = hasObservedMouseDrag
            && probeWindow.isVisible
            && probeWindow.frame.contains(location)
        let shouldFinishMouseDrag = hasEnteredDuringMouseDrag
            && !probeWindow.isFileDragSessionActive
            && !didObserveFileDragInMouseSequence
        let shouldFinishProactiveFileDrag = didTargetFileDragInMouseSequence
            && !probeWindow.isFileDragSessionActive

        mouseDownLocation = nil
        hasObservedMouseDrag = false
        hasEnteredDuringMouseDrag = false
        guard !probeWindow.isFileDragSessionActive else { return }

        if shouldFinishMouseDrag, pendingPlainDragEndLocation == nil {
            pendingPlainDragEndLocation = location
        }
        if shouldFinishProactiveFileDrag, pendingProactiveFileDragEndLocation == nil {
            pendingProactiveFileDragEndLocation = location
        }
        let allowsLateNativeFileDrag = isProactiveFileDragTargeted
            || wasObservedDragReleasedInsideProbe
        if allowsLateNativeFileDrag {
            activateDragEnvelope()
        } else {
            deactivateDragEnvelope()
        }
        scheduleDeferredDisarm(
            of: probeWindow,
            sequenceGeneration: sequenceGeneration,
            allowsLateNativeFileDrag: allowsLateNativeFileDrag
        )
    }

    private func handleFileDragBegan(at location: NSPoint) {
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        if activeMouseSequenceGeneration == nil {
            mouseSequenceGeneration &+= 1
            activeMouseSequenceGeneration = mouseSequenceGeneration
        }
        activateDragEnvelope()
        didObserveFileDragInMouseSequence = true
        didTargetFileDragInMouseSequence = true
        isProactiveFileDragTargeted = true
        hasObservedMouseDrag = true
        hasEnteredDuringMouseDrag = false
        handlers?.onMouseDrag(false, location)
        handlers?.onFileDrag(true, location)
    }

    private func handleFileDragEnded(at location: NSPoint, dropWasAccepted: Bool) {
        stopDragPolling()
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        mouseDownLocation = nil
        hasObservedMouseDrag = false
        hasEnteredDuringMouseDrag = false
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        isProactiveFileDragTargeted = false
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        dragPasteboardChangeCountBeforeMouseSequence = nil
        activeMouseSequenceGeneration = nil
        deactivateDragEnvelope()
        probeWindow?.setArmedForMouseSequence(false)
        handlers?.onFileDrag(false, location)
        handlers?.onFileDragEnded(location, dropWasAccepted)
    }

    private func startDragPolling() {
        guard dragPollingTimer == nil else { return }
        let interval: TimeInterval = 1.0 / 30.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollMouseDrag() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        dragPollingTimer = timer
    }

    private func stopDragPolling() {
        dragPollingTimer?.invalidate()
        dragPollingTimer = nil
    }

    private func scheduleDeferredDisarm(
        of probeWindow: HoverProbeWindow,
        sequenceGeneration: UInt64,
        allowsLateNativeFileDrag: Bool
    ) {
        guard deferredDisarmTask == nil else { return }
        deferredDisarmTask = Task { @MainActor [weak self, weak probeWindow] in
            if allowsLateNativeFileDrag {
                try? await Task.sleep(for: Self.lateNativeFileDragGrace)
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled,
                  let self,
                  let probeWindow,
                  self.mouseDownLocation == nil,
                  self.activeMouseSequenceGeneration == sequenceGeneration,
                  !probeWindow.isFileDragSessionActive else { return }
            if let location = self.pendingPlainDragEndLocation,
               !self.didObserveFileDragInMouseSequence {
                self.handlers?.onMouseDrag(false, location)
                self.handlers?.onMouseDragEnded(location)
            }
            if let location = self.pendingProactiveFileDragEndLocation,
               !probeWindow.isFileDragSessionActive {
                self.isProactiveFileDragTargeted = false
                self.handlers?.onFileDrag(false, location)
                self.handlers?.onFileDragEnded(location, false)
            }
            self.pendingPlainDragEndLocation = nil
            self.pendingProactiveFileDragEndLocation = nil
            self.lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
            self.dragPasteboardChangeCountBeforeMouseSequence = nil
            self.didObserveFileDragInMouseSequence = false
            self.didTargetFileDragInMouseSequence = false
            self.activeMouseSequenceGeneration = nil
            self.deactivateDragEnvelope()
            probeWindow.setArmedForMouseSequence(false)
            self.deferredDisarmTask = nil
        }
    }

    private func pollMouseDrag() {
        guard probeWindow?.isArmedForMouseSequence == true else {
            stopDragPolling()
            return
        }
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            handleMouseUp(at: NSEvent.mouseLocation)
            return
        }
        let location = NSEvent.mouseLocation
        if !hasObservedMouseDrag {
            guard let origin = mouseDownLocation else {
                mouseDownLocation = location
                return
            }
            let dx = location.x - origin.x
            let dy = location.y - origin.y
            guard (dx * dx) + (dy * dy) >= Self.mouseDragThresholdSquared else { return }
            hasObservedMouseDrag = true
        }
        refreshMouseDragContainment(at: location)
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else { return event.locationInWindow }
        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }
}