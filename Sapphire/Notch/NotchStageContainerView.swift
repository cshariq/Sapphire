//
//  NotchStageContainerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import AppKit

enum NotchStageGeometry {
    static func stageFrame(containerSize: CGSize, stageSize: CGSize, backingScale: CGFloat) -> CGRect {
        let scale = backingScale > 0 && backingScale.isFinite ? backingScale : 1
        let x = NotchDisplayMetrics.centeredOriginX(width: stageSize.width, midX: containerSize.width / 2, scale: scale)
        return CGRect(
            x: x,
            y: containerSize.height - stageSize.height,
            width: stageSize.width,
            height: stageSize.height
        )
    }

    static func stagePoint(fromContainerPoint point: CGPoint, stageFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x - stageFrame.minX, y: stageFrame.maxY - point.y)
    }
}

final class NotchStageContainerView: NSView {
    let stageView: NSView
    private(set) var stageSize: CGSize

    init(frame frameRect: NSRect, stageView: NSView, stageSize: CGSize) {
        self.stageView = stageView
        self.stageSize = stageSize
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        stageView.autoresizingMask = []
        addSubview(stageView)
        layoutStage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setStageSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0,
              abs(size.width - stageSize.width) > 0.5 || abs(size.height - stageSize.height) > 0.5 else { return }
        stageSize = size
        layoutStage()
    }

    var stageFrame: CGRect { stageView.frame }

    func stagePoint(fromWindowPoint point: CGPoint) -> CGPoint {
        NotchStageGeometry.stagePoint(fromContainerPoint: convert(point, from: nil), stageFrame: stageView.frame)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutStage()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layoutStage()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutStage()
    }

    private func layoutStage() {
        let frame = NotchStageGeometry.stageFrame(
            containerSize: bounds.size,
            stageSize: stageSize,
            backingScale: window?.backingScaleFactor ?? 2
        )
        if stageView.frame.size != frame.size { stageView.setFrameSize(frame.size) }
        if stageView.frame.origin != frame.origin { stageView.setFrameOrigin(frame.origin) }
    }
}