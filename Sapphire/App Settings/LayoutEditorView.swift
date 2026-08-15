//
//  LayoutEditorView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import SwiftUI

// MARK: - Main Editor View

struct LayoutEditorView: View {
    @Binding var layout: SnapLayout
    let onSave: (SnapLayout) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedZoneID: UUID?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Layout Editor")
                    .font(.title.bold())
                Spacer()
                Button("Done") {
                    onSave(layout)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled($layout.name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }

            TextField("Layout Name", text: $layout.name)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            ZStack {
                GeometryReader { geometry in
                    ZStack {
                        EditorGridPattern(rows: 20, columns: 32)

                        ForEach($layout.zones) { $zone in
                            ResizableView(
                                zone: $zone,
                                isSelected: selectedZoneID == zone.id,
                                canvasSize: geometry.size,
                                allZones: layout.zones
                            )
                            .onTapGesture {
                                selectedZoneID = zone.id
                            }
                        }
                    }
                    .onAppear { canvasSize = geometry.size }
                    .onChange(of: geometry.size) { oldSize, newSize in
                        canvasSize = newSize
                    }
                }
                .aspectRatio(16/10, contentMode: .fit)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
            }

            HStack {
                Button("Add Zone") {
                    let newZone = SnapZone(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                    layout.zones.append(newZone)
                    selectedZoneID = newZone.id
                }
                .buttonStyle(.bordered)

                if selectedZoneID != nil {
                    Button("Remove Selected", role: .destructive) {
                        layout.zones.removeAll { $0.id == selectedZoneID }
                        selectedZoneID = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: 550)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Resizable Zone View

fileprivate struct ResizableView: View {
    @Binding var zone: SnapZone
    let isSelected: Bool
    let canvasSize: CGSize
    let allZones: [SnapZone]

    @State private var dragType: DragType = .none
    @State private var initialRect: CGRect = .zero

    private enum DragType: Equatable {
        case none, move, resize(ResizeHandle)
    }

    var body: some View {
        let frame = zone.toCGRect(in: canvasSize)

        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(isSelected ? 0.5 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.yellow : Color.blue, lineWidth: isSelected ? 3 : 1.5)
                )

            if isSelected {
                ForEach(ResizeHandle.allCases) { handle in
                    ResizeHandleView(handle: handle)
                        .position(handle.position(in: frame))
                        .gesture(resizeGesture(for: handle))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .onHover { isHovering in
            if isHovering { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .gesture(moveGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragType == .none {
                    dragType = .move
                    initialRect = zone.toCGRect(in: canvasSize)
                }
                guard dragType == .move else { return }

                let newOrigin = CGPoint(
                    x: initialRect.origin.x + value.translation.width,
                    y: initialRect.origin.y + value.translation.height
                )

                let snappedFrame = SnappingLogic.snap(
                    frame: CGRect(origin: newOrigin, size: initialRect.size),
                    currentZoneID: zone.id,
                    allZones: allZones,
                    canvasSize: canvasSize,
                    resizing: false
                )

                zone.update(from: snappedFrame, in: canvasSize)
            }
            .onEnded { _ in dragType = .none }
    }

    private func resizeGesture(for handle: ResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragType == .none {
                    dragType = .resize(handle)
                    initialRect = zone.toCGRect(in: canvasSize)
                }
                guard case .resize(let activeHandle) = dragType, activeHandle == handle else { return }

                let newFrame = handle.resize(frame: initialRect, by: value.translation)

                let snappedFrame = SnappingLogic.snap(
                    frame: newFrame,
                    currentZoneID: zone.id,
                    allZones: allZones,
                    canvasSize: canvasSize,
                    resizing: true
                )

                zone.update(from: snappedFrame, in: canvasSize)
            }
            .onEnded { _ in dragType = .none }
    }
}

// MARK: - Resize Handle Utilities

fileprivate enum ResizeHandle: String, CaseIterable, Identifiable {
    case topLeft, top, topRight, leading, trailing, bottomLeft, bottom, bottomRight
    var id: String { rawValue }

    func position(in frame: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: frame.width / 2, y: 0)
        case .topRight: return CGPoint(x: frame.width, y: 0)
        case .leading: return CGPoint(x: 0, y: frame.height / 2)
        case .trailing: return CGPoint(x: frame.width, y: frame.height / 2)
        case .bottomLeft: return CGPoint(x: 0, y: frame.height)
        case .bottom: return CGPoint(x: frame.width / 2, y: frame.height)
        case .bottomRight: return CGPoint(x: frame.width, y: frame.height)
        }
    }

    var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight: return NSCursor.crosshair
        case .topRight, .bottomLeft: return NSCursor.crosshair
        case .top, .bottom: return .resizeUpDown
        case .leading, .trailing: return .resizeLeftRight
        }
    }

    func resize(frame: CGRect, by translation: CGSize) -> CGRect {
        var newFrame = frame
        switch self {
        case .topLeft:
            newFrame.origin.x += translation.width
            newFrame.size.width -= translation.width
            newFrame.origin.y += translation.height
            newFrame.size.height -= translation.height
        case .top:
            newFrame.origin.y += translation.height
            newFrame.size.height -= translation.height
        case .topRight:
            newFrame.size.width += translation.width
            newFrame.origin.y += translation.height
            newFrame.size.height -= translation.height
        case .leading:
            newFrame.origin.x += translation.width
            newFrame.size.width -= translation.width
        case .trailing:
            newFrame.size.width += translation.width
        case .bottomLeft:
            newFrame.origin.x += translation.width
            newFrame.size.width -= translation.width
            newFrame.size.height += translation.height
        case .bottom:
            newFrame.size.height += translation.height
        case .bottomRight:
            newFrame.size.width += translation.width
            newFrame.size.height += translation.height
        }
        return newFrame
    }
}

fileprivate struct ResizeHandleView: View {
    let handle: ResizeHandle

    var body: some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 12, height: 12)
            .onHover { isHovering in
                if isHovering { handle.cursor.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Model & Logic Extensions

fileprivate extension SnapZone {
    func toCGRect(in canvasSize: CGSize) -> CGRect {
        return CGRect(
            x: canvasSize.width * x,
            y: canvasSize.height * y,
            width: canvasSize.width * width,
            height: canvasSize.height * height
        )
    }

    mutating func update(from frame: CGRect, in canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        x = frame.origin.x / canvasSize.width
        y = frame.origin.y / canvasSize.height
        width = frame.width / canvasSize.width
        height = frame.height / canvasSize.height
    }
}

fileprivate struct EditorGridPattern: View {
    let rows: Int
    let columns: Int

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for i in 1..<columns {
                    let xPos = geometry.size.width * CGFloat(i) / CGFloat(columns)
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: geometry.size.height))
                }
                for i in 1..<rows {
                    let yPos = geometry.size.height * CGFloat(i) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: yPos))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: yPos))
                }
            }
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }
}

fileprivate struct SnappingLogic {
    static func snap(frame: CGRect, currentZoneID: UUID, allZones: [SnapZone], canvasSize: CGSize, resizing: Bool, threshold: CGFloat = 8.0) -> CGRect {
        var newFrame = frame
        let otherZoneFrames = allZones.filter { $0.id != currentZoneID }.map {
            $0.toCGRect(in: canvasSize)
        }

        let frameEdgesX: [CGFloat] = [frame.minX, frame.midX, frame.maxX]
        let otherEdgesX: [CGFloat] = otherZoneFrames.flatMap { [$0.minX, $0.midX, $0.maxX] }
        let snapTargetsX: [CGFloat] = [0, canvasSize.width] + otherEdgesX

        for edge in frameEdgesX {
            for target in snapTargetsX {
                if abs(edge - target) < threshold {
                    if edge == frame.minX { newFrame.origin.x = target }
                    else if edge == frame.midX { newFrame.origin.x = target - frame.width / 2 }
                    else { newFrame.origin.x = target - frame.width }
                    break
                }
            }
        }

        let frameEdgesY: [CGFloat] = [frame.minY, frame.midY, frame.maxY]
        let otherEdgesY: [CGFloat] = otherZoneFrames.flatMap { [$0.minY, $0.midY, $0.maxY] }
        let snapTargetsY: [CGFloat] = [0, canvasSize.height] + otherEdgesY

        for edge in frameEdgesY {
            for target in snapTargetsY {
                if abs(edge - target) < threshold {
                    if edge == frame.minY { newFrame.origin.y = target }
                    else if edge == frame.midY { newFrame.origin.y = target - frame.height / 2 }
                    else { newFrame.origin.y = target - frame.height }
                    break
                }
            }
        }

        if newFrame.minX < 0 { newFrame.origin.x = 0 }
        if newFrame.minY < 0 { newFrame.origin.y = 0 }
        if newFrame.maxX > canvasSize.width {
            if resizing { newFrame.size.width = canvasSize.width - newFrame.minX }
            else { newFrame.origin.x = canvasSize.width - newFrame.width }
        }
        if newFrame.maxY > canvasSize.height {
            if resizing { newFrame.size.height = canvasSize.height - newFrame.minY }
            else { newFrame.origin.y = canvasSize.height - newFrame.height }
        }

        return newFrame
    }
}