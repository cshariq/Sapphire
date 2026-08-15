//
//  FileTaskView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-05.
//

import SwiftUI
import NearbyShare
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

private struct HorizontalSwipeActivePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct SwipeToDismissWrapper<Content: View>: View {
    let content: Content
    let onDelete: () -> Void
    let onAction: (() -> Void)?
    let onHover: ((Bool) -> Void)?

    init(onDelete: @escaping () -> Void, onAction: (() -> Void)? = nil, onHover: ((Bool) -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.onDelete = onDelete
        self.onAction = onAction
        self.onHover = onHover
    }

    @State private var offset: CGFloat = 0
    @State private var isSwipingHorizontally = false

    private let deleteThreshold: CGFloat = -80
    private let actionThreshold: CGFloat = 80
    private let releaseAnimation = Animation.spring(response: 0.4, dampingFraction: 0.7)
    private let dragAnimation = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.8, blendDuration: 0.1)

    private var dynamicCornerRadius: CGFloat {
        let startRadius: CGFloat = 30
        let endRadius: CGFloat = 12
        let transitionWidth: CGFloat = 60

        let progress = min(CGFloat(1.0), abs(offset) / transitionWidth)

        return startRadius - (startRadius - endRadius) * progress
    }

    var body: some View {
        ZStack {
            if onAction != nil {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: dynamicCornerRadius, style: .continuous)
                        .fill(Color.blue)
                        .frame(width: max(0, offset))
                        .overlay(
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .opacity(min(1, offset / 40.0))
                                .animation(.easeIn(duration: 0.15), value: offset)
                        )
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: dynamicCornerRadius, style: .continuous)
                    .fill(Color.red)
                    .frame(width: max(0, -offset))
                    .overlay(
                        Image(systemName: "trash.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .opacity(min(1, -offset / 40))
                            .animation(.easeIn(duration: 0.15), value: offset)
                    )
            }

            content
                .contentShape(Rectangle())
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if !isSwipingHorizontally {
                                let w = gesture.translation.width
                                let h = gesture.translation.height
                                if abs(w) > abs(h), abs(w) > 5 {
                                    isSwipingHorizontally = true
                                }
                            }
                            guard isSwipingHorizontally else { return }

                            var newOffset = gesture.translation.width
                            if onAction == nil {
                                newOffset = min(0, newOffset)
                            }

                            withAnimation(dragAnimation) {
                                self.offset = newOffset
                            }
                        }
                        .onEnded { gesture in
                            defer { isSwipingHorizontally = false }

                            if gesture.translation.width < deleteThreshold {
                                withAnimation { onDelete() }
                            } else if gesture.translation.width > actionThreshold, let onAction = onAction {
                                onAction()
                                withAnimation(releaseAnimation) { self.offset = 0 }
                            } else {
                                withAnimation(releaseAnimation) { self.offset = 0 }
                            }
                        }
                    , including: .subviews
                )
                #if os(macOS)
                .overlay(
                    TrackpadSwipeCapture(
                        beginHorizontal: {
                            if !isSwipingHorizontally { isSwipingHorizontally = true }
                        },
                        changeHorizontal: { dx in
                            var proposed = offset - dx
                            if onAction == nil {
                                proposed = min(0, proposed)
                            }
                            withAnimation(dragAnimation) {
                                self.offset = proposed
                            }
                        },
                        endHorizontal: {
                            if self.offset < deleteThreshold {
                                withAnimation { onDelete() }
                            } else if self.offset > actionThreshold, let onAction = onAction {
                                onAction()
                                withAnimation(releaseAnimation) { self.offset = 0 }
                            } else {
                                withAnimation(releaseAnimation) { self.offset = 0 }
                            }
                            isSwipingHorizontally = false
                        }
                    )
                )
                #endif
        }
        .preference(key: HorizontalSwipeActivePreferenceKey.self, value: isSwipingHorizontally)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering in
            onHover?(isHovering)
        }
    }
}

#if os(macOS)
private struct TrackpadSwipeCapture: NSViewRepresentable {
    let beginHorizontal: () -> Void
    let changeHorizontal: (CGFloat) -> Void
    let endHorizontal: () -> Void

    func makeNSView(context: Context) -> NSView {
        return CaptureView(beginHorizontal: beginHorizontal, changeHorizontal: changeHorizontal, endHorizontal: endHorizontal)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CaptureView: NSView {
        let beginHorizontal: () -> Void
        let changeHorizontal: (CGFloat) -> Void
        let endHorizontal: () -> Void

        private var horizontalActive = false

        init(beginHorizontal: @escaping () -> Void,
             changeHorizontal: @escaping (CGFloat) -> Void,
             endHorizontal: @escaping () -> Void) {
            self.beginHorizontal = beginHorizontal
            self.changeHorizontal = changeHorizontal
            self.endHorizontal = endHorizontal
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            if !horizontalActive {
                if abs(dx) > abs(dy), abs(dx) > 0.5 {
                    horizontalActive = true
                    beginHorizontal()
                } else {
                    nextResponder?.scrollWheel(with: event)
                    return
                }
            }

            if event.phase == .ended || event.momentumPhase == .ended || event.phase == .cancelled {
                horizontalActive = false
                endHorizontal()
                return
            }

            changeHorizontal(dx)
        }
    }
}
#endif

struct FileTaskView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    @StateObject private var fileDropManager = FileDropManager.shared
    @StateObject private var shelfManager = FileShelfManager.shared
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @EnvironmentObject private var fileShelfState: FileShelfState

    @State private var isShowing = false
    @State private var isAnyRowSwiping = false

    private var allItems: [FileTask] {
        let liveTasks = fileDropManager.tasks
        let shelfTasks = shelfManager.files.map { FileTask.local($0) }

        return (liveTasks + shelfTasks).sorted { item1, item2 in
            let dateA: Date = {
                switch item1 {
                case .local(let item): return item.dateAdded
                default: return Date()
                }
            }()
            let dateB: Date = {
                switch item2 {
                case .local(let item): return item.dateAdded
                default: return Date()
                }
            }()
            return dateA > dateB
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(onOpenShelf: { navigationStack.append(.fileShelf) })

            contentBody
        }
        .frame(width: 600)
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environmentObject(liveActivityManager)
        .scaleEffect(isShowing ? 1 : 0.98)
        .opacity(isShowing ? 1 : 0)
        .padding(.top, 1)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isShowing = true
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        Group {
            if allItems.isEmpty {
                EmptyStateView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(allItems) { item in
                            UnifiedRowView(item: item, onSelectDetails: { shelfItem in
                                fileShelfState.selectedItemForPreview = shelfItem
                            })
                            .animation(.spring(), value: allItems)
                            .transition(.opacity)
                        }
                    }
                    .padding(8)
                }
                .scrollDisabled(isAnyRowSwiping)
                .onPreferenceChange(HorizontalSwipeActivePreferenceKey.self) { value in
                    isAnyRowSwiping = value
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: allItems.isEmpty)
    }
}

private struct UnifiedRowView: View {
    let item: FileTask
    let onSelectDetails: (ShelfItem) -> Void

    var body: some View {
        switch item {
        case .incomingTransfer(let transfer):
            SwipeToDismissWrapper(
                onDelete: {
                    switch transfer.state {
                    case .waiting:
                        NearbyConnectionManager.shared.submitUserConsent(transferID: transfer.id, accept: false)
                    case .inProgress:
                        NearbyConnectionManager.shared.cancelIncomingTransfer(id: transfer.id)
                    default:
                        FileDropManager.shared.removeTask(withID: item.id)
                    }
                }
            ) {
                ModernTransferRowView(transfer: transfer, onSelectDetails: onSelectDetails)
            }
        case .universalTransfer(let transferTask):
            SwipeToDismissWrapper(onDelete: { FileDropManager.shared.removeTask(withID: item.id) }) {
                UniversalTransferRowView(task: transferTask)
            }
        case .airDrop(let airDropTask):
            SwipeToDismissWrapper(onDelete: { FileDropManager.shared.removeTask(withID: item.id) }) {
                AirDropRowView(task: airDropTask)
            }
        case .fileConversion(let conversionTask):
            SwipeToDismissWrapper(onDelete: { FileDropManager.shared.removeTask(withID: item.id) }) {
                ConversionRowView(task: conversionTask)
            }
        case .local(let shelfItem):
            LocalFileRowWithHover(item: shelfItem, onSelectDetails: onSelectDetails)
        }
    }
}

private struct LocalFileRowWithHover: View {
    let item: ShelfItem
    let onSelectDetails: (ShelfItem) -> Void
    @State private var isHovering = false

    var body: some View {
        SwipeToDismissWrapper(
            onDelete: { FileShelfManager.shared.removeFile(item) },
            onAction: {
                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.storedAt])
            },
            onHover: { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hovering
                }
            }
        ) {
            LocalFileRowView(item: item, onSelectDetails: onSelectDetails, isHovering: isHovering)
        }
    }
}

private struct HeaderView: View {
    var onOpenShelf: () -> Void

    var body: some View {
        HStack {
            Image(privateName: "shareplay")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)

            Text("File Drops")
                .font(.headline)
                .fontWeight(.bold)

            Spacer()

            Button(action: onOpenShelf) {
                Image(systemName: "tray.2.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(.black.opacity(0.3))
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text("No Active Files or Shelf Items")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding()
    }
}

private struct UniversalTransferRowView: View {
    let task: FileTransferTask

    private var subtitle: String {
        let sizeString = ByteCountFormatter.string(fromByteCount: task.currentSize, countStyle: .file)
        if task.isComplete {
            return "Complete (\(sizeString))"
        }
        if task.totalSize != nil {
            return "Downloading... (\(sizeString))"
        } else {
            return "Copying... (\(sizeString))"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            TaskIconView(systemName: "arrow.down.circle.fill", color: .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName).font(.callout).fontWeight(.semibold).lineLimit(1)
                Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)

            if task.isComplete {
                StatusIcon(systemName: "checkmark.circle.fill", color: .green)
            } else if let progress = task.progress {
                ProgressIndicator(progress: progress, color: .blue)
            } else {
                ProgressView().progressViewStyle(.circular).controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LocalFileRowView: View {
    let item: ShelfItem
    let onSelectDetails: (ShelfItem) -> Void
    @StateObject private var manager = FileShelfManager.shared

    let isHovering: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                TaskIconView(systemName: IconGenerator.symbolName(for: item), color: .secondary)

                if isHovering {
                    Button(action: { manager.removeFile(item) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.callout)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .transition(.scale.animation(.spring(response: 0.2, dampingFraction: 0.6)))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName).font(.callout).fontWeight(.semibold).lineLimit(1)
                Text("On Shelf").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)

            if isHovering {
                ActionButtons(item: item, onSelectDetails: onSelectDetails)
            }
        }
        .padding(10)
        .background(Color.black.opacity(isHovering ? 0.2 : 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDrag {
            DragStateManager.shared.isDraggingFromShelf = true
            return NSItemProvider(object: item.storedAt as NSURL)
        }
    }
}

private struct AirDropRowView: View {
    let task: AirDropTask

    var body: some View {
        HStack(spacing: 12) {
            TaskIconView(systemName: "airplayaudio", color: .cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName).font(.callout).fontWeight(.semibold).lineLimit(1)
                Text("Receiving via AirDrop...").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)

            if task.isComplete {
                StatusIcon(systemName: "checkmark.circle.fill", color: .green)
            } else {
                ProgressIndicator(progress: task.progress, color: .cyan)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ConversionRowView: View {
    let task: ConversionTask

    var body: some View {
        HStack(spacing: 12) {
            TaskIconView(systemName: task.sourceIcon, color: .purple)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName).font(.callout).fontWeight(.semibold).lineLimit(1)
                Text("Converting to \(task.targetFormat.displayName)").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)

            switch task.status {
            case .inProgress:
                ProgressIndicator(progress: task.progress, color: .purple)
            case .done:
                StatusIcon(systemName: "checkmark.circle.fill", color: .green)
            case .failed:
                StatusIcon(systemName: "xmark.circle.fill", color: .red)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ModernTransferRowView: View {
    let transfer: TransferProgressInfo
    let onSelectDetails: (ShelfItem) -> Void
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @State private var isHovering = false

    private var shelfItemForCompletedTransfer: ShelfItem? {
        guard transfer.state == .finished,
              let payload = liveActivityManager.currentNearDropPayload,
              payload.id == transfer.id,
              let url = payload.destinationURLs.first else {
            return nil
        }
        return ShelfItem(id: UUID(), storedAt: url, dateAdded: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            TaskIconView(systemName: transfer.iconName, color: .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(transfer.deviceName).font(.callout).fontWeight(.semibold).lineLimit(1)
                Text(transfer.fileDescription).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)

            trailingItem
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: transfer.state)
        }
        .padding(10)
        .background(Color.black.opacity(isHovering ? 0.2 : 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var trailingItem: some View {
        switch transfer.state {
        case .waiting:
            IntegratedActionIconButtonsView(transfer: transfer)
                .environmentObject(liveActivityManager)
        case .inProgress:
            ProgressIndicator(progress: transfer.progress, color: .accentColor)
        case .finished:
            if isHovering, let item = shelfItemForCompletedTransfer {
                ActionButtons(item: item, onSelectDetails: onSelectDetails)
            } else {
                StatusIcon(systemName: "checkmark.circle.fill", color: .green)
            }
        case .failed:
            StatusIcon(systemName: "xmark.circle.fill", color: .red)
        case .canceled:
            StatusIcon(systemName: "xmark.circle.fill", color: .gray)
        }
    }
}

private struct TaskIconView: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.15))
            Image(systemName: systemName).font(.title3).foregroundColor(color)
        }.frame(width: 44, height: 44)
    }
}

private struct ActionButtons: View {
    let item: ShelfItem
    let onSelectDetails: (ShelfItem) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.storedAt])
            }) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(ModernIconActionButtonStyle(isProminent: false))

            Button(action: { onSelectDetails(item) }) {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(ModernIconActionButtonStyle(isProminent: true))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

private struct IntegratedActionIconButtonsView: View {
    let transfer: TransferProgressInfo
    @EnvironmentObject var liveActivityManager: LiveActivityManager

    private func submitConsent(accept: Bool, action: NearDropUserAction = .save) {
        liveActivityManager.clearNearDropActivity(id: transfer.id)
        NearbyConnectionManager.shared.submitUserConsent(transferID: transfer.id, accept: accept, action: action)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { submitConsent(accept: false) } label: { Image(systemName: "xmark") }
                .buttonStyle(ModernIconActionButtonStyle(isProminent: false))
            Button { submitConsent(accept: true, action: .save) } label: { Image(systemName: "checkmark") }
                .buttonStyle(ModernIconActionButtonStyle(isProminent: true))
        }
    }
}

private struct ProgressIndicator: View {
    let progress: Double
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 4.0).opacity(0.2).foregroundColor(color)
            Circle().trim(from: 0.0, to: CGFloat(min(self.progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .rotationEffect(Angle(degrees: 270.0))
            Text("\(Int(progress * 100))%").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
        }
        .frame(width: 36, height: 36)
    }
}

private struct StatusIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(color)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

private struct ModernIconActionButtonStyle: ButtonStyle {
    var isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isProminent ? .white : .primary)
            .frame(width: 32, height: 32)
            .background(isProminent ? Color.accentColor : Color.secondary.opacity(0.25))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct IconGenerator {
    static func symbolName(for item: ShelfItem) -> String {
        guard let type = try? item.storedAt.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return "doc.fill"
        }

        if type.conforms(to: .image) { return "photo.fill" }
        if type.conforms(to: .movie) { return "video.fill" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext.fill" }
        if type.conforms(to: .text) { return "doc.text.fill" }
        if type.conforms(to: .folder) { return "folder.fill" }
        if type.conforms(to: .archive) { return "archivebox.fill" }

        return "doc.fill"
    }
}