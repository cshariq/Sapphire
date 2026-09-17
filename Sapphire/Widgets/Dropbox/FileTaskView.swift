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
    let leading: NotchSwipeAction?
    let trailing: NotchSwipeAction?
    let content: Content
    let onHover: ((Bool) -> Void)?

    init(leading: NotchSwipeAction? = nil, trailing: NotchSwipeAction? = nil, onHover: ((Bool) -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.leading = leading
        self.trailing = trailing
        self.content = content()
        self.onHover = onHover
    }

    @State private var offset: CGFloat = 0
    @State private var isSwipingHorizontally = false

    private let leadingThreshold: CGFloat = 80
    private let trailingThreshold: CGFloat = -80
    private let releaseAnimation = Animation.spring(response: 0.4, dampingFraction: 0.7)

    private var dynamicCornerRadius: CGFloat {
        let startRadius: CGFloat = 30
        let endRadius: CGFloat = 12
        let transitionWidth: CGFloat = 60

        let progress = min(CGFloat(1.0), abs(offset) / transitionWidth)

        return startRadius - (startRadius - endRadius) * progress
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if let leading {
                    RoundedRectangle(cornerRadius: dynamicCornerRadius, style: .continuous)
                        .fill(leading.tint)
                        .frame(width: max(0, offset))
                        .overlay(
                            Image(systemName: leading.systemImage)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .opacity(min(1, offset / 40.0))
                                .animation(.easeIn(duration: 0.15), value: offset)
                        )
                }
                Spacer(minLength: 0)
                if let trailing {
                    RoundedRectangle(cornerRadius: dynamicCornerRadius, style: .continuous)
                        .fill(trailing.tint)
                        .frame(width: max(0, -offset))
                        .overlay(
                            Image(systemName: trailing.systemImage)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .opacity(min(1, -offset / 40))
                                .animation(.easeIn(duration: 0.15), value: offset)
                        )
                }
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
                            if leading == nil { newOffset = min(0, newOffset) }
                            if trailing == nil { newOffset = max(0, newOffset) }

                            self.offset = newOffset
                        }
                        .onEnded { gesture in
                            defer { isSwipingHorizontally = false }
                            settle()
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
                            if leading == nil { proposed = min(0, proposed) }
                            if trailing == nil { proposed = max(0, proposed) }
                            self.offset = proposed
                        },
                        endHorizontal: {
                            settle()
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

    private func settle() {
        if offset > leadingThreshold, let leading {
            leading.handler()
            withAnimation(releaseAnimation) { offset = 0 }
        } else if offset < trailingThreshold, let trailing {
            trailing.handler()
            withAnimation(releaseAnimation) { offset = 0 }
        } else {
            withAnimation(releaseAnimation) { offset = 0 }
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

    @EnvironmentObject var settings: SettingsModel
    @StateObject private var fileDropManager = FileDropManager.shared
    @StateObject private var shelfManager = FileShelfManager.shared
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @EnvironmentObject private var fileShelfState: FileShelfState

    @State private var isShowing = false
    @State private var isAnyRowSwiping = false

    private var allItems: [FileTask] {
        let liveTasks = fileDropManager.tasks
        let shelfTasks = shelfManager.files
            .sorted { $0.dateAdded > $1.dateAdded }
            .map(FileTask.local)

        return liveTasks + shelfTasks
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
        let items = allItems
        Group {
            if items.isEmpty {
                EmptyStateView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            UnifiedRowView(item: item, onSelectDetails: { shelfItem in
                                fileShelfState.selectedItemForPreview = shelfItem
                            })
                            .transition(.opacity)
                        }
                    }
                    .padding(8)
                    .animation(.spring(), value: items.map(\.id))
                }
                .scrollDisabled(isAnyRowSwiping)
                .onPreferenceChange(HorizontalSwipeActivePreferenceKey.self) { value in
                    isAnyRowSwiping = value
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: items.isEmpty)
    }
}

private struct UnifiedRowView: View {
    let item: FileTask
    let onSelectDetails: (ShelfItem) -> Void
    @EnvironmentObject var settings: SettingsModel

    private var leadingAction: NotchSwipeAction? {
        swipeAction(settings.settings.swipeActionSettings.fileDropLeading)
    }

    private var trailingAction: NotchSwipeAction? {
        swipeAction(settings.settings.swipeActionSettings.fileDropTrailing)
    }

    var body: some View {
        switch item {
        case .incomingTransfer(let transfer):
            SwipeToDismissWrapper(leading: leadingAction, trailing: trailingAction) {
                ModernTransferRowView(transfer: transfer, onSelectDetails: onSelectDetails)
            }
        case .universalTransfer(let transferTask):
            SwipeToDismissWrapper(leading: leadingAction, trailing: trailingAction) {
                UniversalTransferRowView(task: transferTask)
            }
        case .airDrop(let airDropTask):
            SwipeToDismissWrapper(leading: leadingAction, trailing: trailingAction) {
                AirDropRowView(task: airDropTask)
            }
        case .fileConversion(let conversionTask):
            SwipeToDismissWrapper(leading: leadingAction, trailing: trailingAction) {
                ConversionRowView(task: conversionTask)
            }
        case .local(let shelfItem):
            LocalFileRowWithHover(
                item: shelfItem,
                onSelectDetails: onSelectDetails,
                leading: leadingAction,
                trailing: trailingAction
            )
        }
    }

    private func swipeAction(_ action: FileDropSwipeAction) -> NotchSwipeAction? {
        switch action {
        case .none:
            return nil
        case .delete:
            return NotchSwipeAction(systemImage: "trash.fill", tint: .red) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    delete(item)
                }
            }
        case .share:
            guard case .local(let shelfItem) = item else { return nil }
            return NotchSwipeAction(systemImage: "square.and.arrow.up", tint: .blue) {
                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [shelfItem.storedAt])
            }
        }
    }

    private func delete(_ item: FileTask) {
        switch item {
        case .incomingTransfer(let transfer):
            switch transfer.state {
            case .waiting:
                NearbyConnectionManager.shared.submitUserConsent(transferID: transfer.id, accept: false)
            case .inProgress:
                NearbyConnectionManager.shared.cancelIncomingTransfer(id: transfer.id)
            default:
                FileDropManager.shared.removeTask(withID: item.id)
            }
        case .local(let shelfItem):
            FileShelfManager.shared.removeFile(shelfItem)
        default:
            FileDropManager.shared.removeTask(withID: item.id)
        }
    }
}

private struct LocalFileRowWithHover: View {
    let item: ShelfItem
    let onSelectDetails: (ShelfItem) -> Void
    let leading: NotchSwipeAction?
    let trailing: NotchSwipeAction?
    @State private var isHovering = false

    var body: some View {
        SwipeToDismissWrapper(
            leading: leading,
            trailing: trailing,
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

    private var verb: String {
        switch task.sourceType {
        case .finder: return "Copying"
        case .archiveExtraction: return "Extracting"
        case .dmgInstall: return "Installing"
        case .browserDownload, .manual: return "Downloading"
        }
    }

    private var icon: String {
        switch task.sourceType {
        case .finder: return "arrow.right.arrow.left.circle.fill"
        case .archiveExtraction: return "archivebox.fill"
        case .dmgInstall: return "externaldrive.fill.badge.plus"
        case .browserDownload, .manual: return "arrow.down.circle.fill"
        }
    }

    private var tint: Color {
        switch task.sourceType {
        case .archiveExtraction: return .brown
        case .dmgInstall: return .indigo
        default: return .blue
        }
    }

    private var subtitle: String {
        let sizeString = ByteFormatter.string(task.currentSize)
        guard !task.isComplete else { return "Complete (\(sizeString))" }

        var parts = ["\(verb)..."]
        if let total = task.totalSize {
            parts.append("\(sizeString) of \(ByteFormatter.string(total))")
        } else {
            parts.append(sizeString)
        }
        if task.speed > 0 {
            parts.append(TransferMetricsFormatter.speed(task.speed))
        }
        if let eta = TransferMetricsFormatter.eta(
            currentBytes: task.currentSize,
            totalBytes: task.totalSize,
            bytesPerSecond: task.speed
        ) {
            parts.append("\(eta) left")
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        HStack(spacing: 12) {
            TaskIconView(systemName: icon, color: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName).font(.callout).fontWeight(.semibold).lineLimit(1)
                Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)

            if task.isComplete {
                StatusIcon(systemName: "checkmark.circle.fill", color: .green)
            } else if let progress = task.progress {
                ProgressIndicator(progress: progress, color: tint)
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
                LocalFileIconView(url: item.storedAt)

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
            DragStateManager.shared.beginShelfDrag(item: item)
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
            .buttonStyle(CircleIconButtonStyle(type: .normal, size: .small))

            Button(action: { onSelectDetails(item) }) {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(CircleIconButtonStyle(type: .prominent, size: .small))
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
                .buttonStyle(CircleIconButtonStyle(type: .normal, size: .small))
            Button { submitConsent(accept: true, action: .save) } label: { Image(systemName: "checkmark") }
                .buttonStyle(CircleIconButtonStyle(type: .prominent, size: .small))
        }
    }
}

private struct ProgressIndicator: View {
    let progress: Double
    let color: Color
    var body: some View {
        ZStack {
            ProgressRingView(
                progress: progress,
                lineWidth: 4.0,
                track: AnyShapeStyle(color.opacity(0.2)),
                active: color,
                rotation: .degrees(270)
            )
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

private struct LocalFileIconView: View {
    let url: URL
    @State private var systemName = "doc.fill"

    var body: some View {
        TaskIconView(systemName: systemName, color: .secondary)
            .task(id: url) {
                let loadedName = await Task.detached(priority: .utility) {
                    url.sapphireFileSymbolName
                }.value
                guard !Task.isCancelled else { return }
                systemName = loadedName
            }
    }
}