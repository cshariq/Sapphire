//
//  AppIconView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Helper Models & Extensions
extension SystemApp {
    var isDeletable: Bool {
        !url.path.starts(with: "/System")
    }
}

// MARK: - PreferenceKeys for Reading View Frames
struct ItemFramePreferenceKey: PreferenceKey {
    typealias Value = [String: CGRect]
    static var defaultValue: Value = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

struct FolderFramePreferenceKey: PreferenceKey {
    typealias Value = CGRect
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Launchpad View Model
@MainActor
class LaunchpadViewModel: ObservableObject {
    @Published var pages: [[LaunchpadPageItem]] = []
    @Published var currentPage: Int = 0
    @Published var searchText: String = ""
    @Published var filteredApps: [SystemApp] = []
    @Published var draggingItem: LaunchpadPageItem?

    @Published var folderCreationTargetID: String?
    private var reorderTimer: Timer?
    private var pendingReorderPath: (page: Int, item: Int)?

    var dragOriginPath: (page: Int, item: Int)?

    @Published var itemToDelete: LaunchpadPageItem?
    @Published var showingDeleteConfirm = false
    var deleteAlertTitle: String {
        guard let item = itemToDelete else { return "" }
        switch item {
        case .app(let appItem):
            return "Move \"\(getApp(for: appItem)?.name ?? "App")\" to Trash?"
        case .folder:
            return "Disband Folder?"
        }
    }
    var deleteAlertMessage: String {
        guard let item = itemToDelete else { return "" }
        switch item {
        case .app:
            return "This will permanently remove the app from your Mac."
        case .folder(let folder):
            return "The apps in \"\(folder.name)\" will be returned to the Launchpad."
        }
    }

    let dropPlaceholderID = "dropPlaceholder"

    private var allApps: [SystemApp] = []; private let appFetcher = SystemAppFetcher.shared; private var settingsModel = SettingsModel.shared; private var cancellables = Set<AnyCancellable>()
    private let appsPerPage = 6 * 5

    init() {
        appFetcher.$apps.filter { !$0.isEmpty }.first().receive(on: DispatchQueue.main).sink { [weak self] apps in self?.allApps = apps; self?.synchronizeLayout() }.store(in: &cancellables)
        $searchText.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main).removeDuplicates().sink { [weak self] text in self?.filterApps(with: text) }.store(in: &cancellables)
    }

    func fetchApps() { appFetcher.fetchApps() }

    private func synchronizeLayout() {
        let savedLayout = settingsModel.settings.launchpadLayout
        if savedLayout.isEmpty {
            let defaultItems = allApps.map { LaunchpadPageItem.app(LaunchpadItem(appBundleID: $0.id)) }
            self.pages = stride(from: 0, to: defaultItems.count, by: appsPerPage).map { Array(defaultItems[$0..<min($0 + appsPerPage, defaultItems.count)]) }
        } else {
            self.pages = savedLayout.map { page in
                page.compactMap { item in
                    switch item {
                    case .app(let appItem): return appFetcher.foundBundleIDs.contains(appItem.appBundleID) ? item : nil
                    case .folder(var folder):
                        folder.items = folder.items.filter { appFetcher.foundBundleIDs.contains($0.appBundleID) }
                        return folder.items.isEmpty ? nil : .folder(folder)
                    }
                }
            }
        }
        reflowAndCompactLayout()
    }

    private func saveLayout() {
        settingsModel.settings.launchpadLayout = pages.map { $0.filter { $0.id != dropPlaceholderID } }
    }

    func reflowAndCompactLayout() {
        removeDropPlaceholder()

        let allCurrentItems = pages.flatMap { $0 }
        var processedItems: [LaunchpadPageItem] = []
        var seenIDs = Set<String>()

        for item in allCurrentItems {
            if seenIDs.contains(item.id) {
                print("WARNING: Duplicate item ID found and removed during reflow: \(item.id)")
                continue
            }

            if case .folder(let folder) = item {
                if folder.items.count <= 1 {
                    seenIDs.insert(item.id)
                    for appItem in folder.items {
                        if !seenIDs.contains(appItem.id) {
                            processedItems.append(.app(appItem))
                            seenIDs.insert(appItem.id)
                        } else {
                             print("WARNING: Duplicate app \(appItem.appBundleID) found when disbanding folder. Ignoring.")
                        }
                    }
                } else {
                    processedItems.append(item)
                    seenIDs.insert(item.id)
                }
            } else {
                processedItems.append(item)
                seenIDs.insert(item.id)
            }
        }

        var newPages: [[LaunchpadPageItem]] = []
        if !processedItems.isEmpty {
            newPages = stride(from: 0, to: processedItems.count, by: appsPerPage).map {
                Array(processedItems[$0..<min($0 + appsPerPage, processedItems.count)])
            }
        }

        if newPages.isEmpty {
            newPages.append([])
        }

        DispatchQueue.main.async {
            self.pages = newPages
            if self.currentPage >= self.pages.count {
                self.currentPage = max(0, self.pages.count - 1)
            }
            self.saveLayout()
        }
    }

    func getApp(for item: LaunchpadItem) -> SystemApp? { return allApps.first { $0.id == item.appBundleID } }

    private func filterApps(with query: String) {
        if query.isEmpty { filteredApps = [] } else { filteredApps = allApps.filter { $0.name.localizedCaseInsensitiveContains(query) } }
    }

    func createFolder(with draggedItem: LaunchpadItem, on targetItem: LaunchpadPageItem) {
        guard case let .app(targetAppItem) = targetItem else { return }
        let newFolder = LaunchpadFolder(id: UUID(), name: "Folder", items: [targetAppItem, draggedItem])
        guard let targetPath = findPath(for: targetItem.id) else { return }

        draggingItem = nil
        dragOriginPath = nil
        cancelReorderTimer()
        folderCreationTargetID = nil

        removeDropPlaceholder()
        pages[targetPath.page][targetPath.item] = .folder(newFolder)
        reflowAndCompactLayout()
    }

    func addToFolder(_ draggedItem: LaunchpadItem, to targetFolder: LaunchpadFolder) {
        var updatedFolder = targetFolder
        updatedFolder.items.append(draggedItem)
        guard let targetPath = findPath(for: targetFolder.id.uuidString) else { return }

        draggingItem = nil
        dragOriginPath = nil
        cancelReorderTimer()
        folderCreationTargetID = nil

        removeDropPlaceholder()
        pages[targetPath.page][targetPath.item] = .folder(updatedFolder)
        reflowAndCompactLayout()
    }

    func beginDragFromFolder(item: LaunchpadItem, from folderID: UUID) {
        guard let folderPath = findPath(for: folderID.uuidString) else { return }
        guard case .folder(var folder) = pages[folderPath.page][folderPath.item] else { return }

        folder.items.removeAll { $0.id == item.id }
        pages[folderPath.page][folderPath.item] = .folder(folder)

        self.draggingItem = .app(item)
        reflowAndCompactLayout()
    }

    func findPath(for itemToFindID: String) -> (page: Int, item: Int)? {
        for (pageIndex, page) in pages.enumerated() {
            if let itemIndex = page.firstIndex(where: { $0.id == itemToFindID }) {
                return (pageIndex, itemIndex)
            }
        }
        return nil
    }

    private func insertDropPlaceholder(at path: (page: Int, item: Int)) {
        if let oldPath = findPath(for: dropPlaceholderID) {
            if oldPath.page == path.page && oldPath.item == path.item { return }
            pages[oldPath.page].remove(at: oldPath.item)
        }

        if pages.indices.contains(path.page) {
            pages[path.page].insert(LaunchpadPageItem.app(LaunchpadItem(appBundleID: dropPlaceholderID)), at: min(path.item, pages[path.page].count))
        }
    }

    func removeDropPlaceholder() {
        if let path = findPath(for: dropPlaceholderID) {
            pages[path.page].remove(at: path.item)
        }
    }

    func finalizeDrop(of draggedItem: LaunchpadPageItem) {
        if let placeholderPath = findPath(for: dropPlaceholderID) {
            removeDropPlaceholder()
            pages[placeholderPath.page].insert(draggedItem, at: min(placeholderPath.item, pages[placeholderPath.page].count))
        } else if let originPath = dragOriginPath {
            pages[originPath.page].insert(draggedItem, at: min(originPath.item, pages[originPath.page].count))
        }

        dragOriginPath = nil
        reflowAndCompactLayout()
    }

    func startReorderTimer(at path: (page: Int, item: Int)) {
        if pendingReorderPath?.page == path.page && pendingReorderPath?.item == path.item { return }

        cancelReorderTimer()
        pendingReorderPath = path

        reorderTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let self = self, let pendingPath = self.pendingReorderPath else { return }
            self.insertDropPlaceholder(at: pendingPath)
        }
    }

    func cancelReorderTimer() {
        reorderTimer?.invalidate()
        reorderTimer = nil
        pendingReorderPath = nil
    }

    func requestDeleteItem(_ item: LaunchpadPageItem) {
        self.itemToDelete = item
        self.showingDeleteConfirm = true
    }

    func confirmDeleteItem() {
        guard let item = itemToDelete, let path = findPath(for: item.id) else {
            cancelDeleteItem()
            return
        }

        switch item {
        case .app(let appItem):
            guard let app = getApp(for: appItem), app.isDeletable else { break }
            do {
                try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
                pages[path.page].remove(at: path.item)
                reflowAndCompactLayout()
            } catch {
                print("Error moving item to trash: \(error)")
            }

        case .folder(let folderItem):
            let itemsToUnfold = folderItem.items.map { LaunchpadPageItem.app($0) }
            pages[path.page].remove(at: path.item)
            pages[path.page].insert(contentsOf: itemsToUnfold, at: path.item)
            reflowAndCompactLayout()
        }

        cancelDeleteItem()
    }

    func cancelDeleteItem() {
        itemToDelete = nil
        showingDeleteConfirm = false
    }
}

// MARK: - Component Views
struct DeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.black.opacity(0.5))
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white)
            }.frame(width: 20, height: 20)
        }.buttonStyle(.plain)
    }
}

struct SearchBar: View {
    @Binding var text: String; var isFocused: FocusState<Bool>.Binding
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.white.opacity(0.5)).font(.system(size: 15, weight: .semibold))
            ZStack(alignment: .leading) {
                Text("Search").foregroundColor(.white.opacity(0.5)).font(.system(size: 16, weight: .regular)).opacity(text.isEmpty && !isFocused.wrappedValue ? 1 : 0)
                TextField("", text: $text).focused(isFocused).textFieldStyle(.plain).foregroundColor(.white).font(.system(size: 16, weight: .regular))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7).background(Color.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1)).frame(width: 250)
    }
}

struct FolderIconView: View {
    let folder: LaunchpadFolder; let viewModel: LaunchpadViewModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle().fill(.black.opacity(0.3)).frame(width: 110, height: 110).cornerRadius(26)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(folder.items.prefix(4)) { item in
                        if let app = viewModel.getApp(for: item) { Image(nsImage: app.icon).resizable().aspectRatio(contentMode: .fit).frame(width: 42, height: 42) }
                    }
                }.padding(8)
            }.frame(width: 110, height: 110)
            Text(folder.name).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
        }
    }
}

struct AppIconView: View {
    let app: SystemApp; let isHovered: Bool
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: app.icon).resizable().aspectRatio(contentMode: .fit)
            Text(app.name).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1).truncationMode(.tail).frame(maxWidth: 110)
        }
    }
}

struct LaunchpadItemView: View {
    let item: LaunchpadPageItem
    let isHovered: Bool
    let isJiggling: Bool
    let isFolderTarget: Bool

    @EnvironmentObject var viewModel: LaunchpadViewModel

    private var isDeletable: Bool {
        switch item {
        case .app(let appItem):
            return viewModel.getApp(for: appItem)?.isDeletable ?? false
        case .folder:
            return true
        }
    }

    var body: some View {
        ZStack {
            if isFolderTarget {
                Rectangle()
                    .fill(.black.opacity(0.3))
                    .frame(width: 110, height: 110)
                    .cornerRadius(26)
                    .transition(.opacity.animation(.easeInOut))
            }

            Group {
                switch item {
                case .app:
                    if let appItem = item.appItem, let app = viewModel.getApp(for: appItem) {
                        AppIconView(app: app, isHovered: isHovered)
                            .scaleEffect(isFolderTarget ? 0.75 : 1.0)
                    }
                case .folder(let folderItem):
                    FolderIconView(folder: folderItem, viewModel: viewModel)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFolderTarget)
        }
        .frame(width: 110, height: 144)
        .overlay(alignment: .topLeading) {
            if isJiggling && isDeletable {
                DeleteButton { viewModel.requestDeleteItem(item) }
                .offset(x: -4, y: -4)
                .transition(.scale.animation(.spring()))
            }
        }
    }
}

// MARK: - Main Launchpad View
struct LaunchpadView: View {
    @StateObject private var viewModel = LaunchpadViewModel()
    @EnvironmentObject private var gestureManager: LaunchpadGestureManager

    let interceptor: LaunchpadInputInterceptor
    let backgroundImage: NSImage?; let bottomPadding: CGFloat

    @FocusState private var searchFieldIsFocused: Bool

    @State private var hoveredItemID: String?
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var pageFrames: [Int: CGRect] = [:]
    @State private var gridMetrics = (
        columns: 6,
        rows: 5,
        itemWidth: 110.0,
        itemHeight: 144.0,
        horizontalSpacing: 25.0,
        verticalSpacing: 25.0
    )
    @State private var isJiggleMode: Bool = false
    @State private var openedFolder: LaunchpadFolder?
    @State private var edgeSwipeTimer: Timer?
    private enum SwipeDirection { case left, right }
    private let horizontalPadding: CGFloat = 180

    private var columns: [GridItem] {
        Array(repeating: .init(.flexible(), spacing: gridMetrics.horizontalSpacing), count: gridMetrics.columns)
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if isJiggleMode { isJiggleMode = false }
                    else if openedFolder != nil { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { openedFolder = nil } }
                    else { NotificationCenter.default.post(name: .requestCloseLaunchpad, object: nil) }
                }

            Group {
                if let bgImage = backgroundImage {
                    Image(nsImage: bgImage).resizable().aspectRatio(contentMode: .fill).ignoresSafeArea().allowsHitTesting(false)
                }
                VStack(spacing: 0) {
                    Color.clear.frame(height: 60).contentShape(Rectangle())
                    SearchBar(text: $viewModel.searchText, isFocused: $searchFieldIsFocused)
                        .padding(.bottom, 40)

                    if viewModel.searchText.isEmpty { paginatedView } else { searchResultsView }
                }
                if viewModel.searchText.isEmpty && viewModel.pages.count > 1 {
                    VStack {
                        Spacer()
                        paginationDots.padding(.bottom, 60 + bottomPadding)
                    }
                }
                if let draggedItem = viewModel.draggingItem {
                    LaunchpadItemView(item: draggedItem, isHovered: false, isJiggling: false, isFolderTarget: false).position(gestureManager.mouseLocation)
                }
            }
            .blur(radius: openedFolder != nil ? 20 : 0)
            .allowsHitTesting(openedFolder == nil)

            if let folder = openedFolder { folderDetailView(folder: folder) }
        }
        .onAppear { viewModel.fetchApps() }
        .onExitCommand {
            if isJiggleMode { isJiggleMode = false }
            else if openedFolder != nil { openedFolder = nil }
            else { NotificationCenter.default.post(name: .requestCloseLaunchpad, object: nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userStartedTypingInLaunchpad)) { _ in self.searchFieldIsFocused = true }
        .onReceive(gestureManager.$mouseLocation) { location in
            guard gestureManager.isDraggingItem else {
                hoveredItemID = itemFrames.first { $0.value.contains(location) }?.key
                return
            }
            hoveredItemID = nil
            handleDragChange(at: location)
        }
        .onReceive(gestureManager.clickOccurred) { location in
            if !isJiggleMode {
                if let (itemID, _) = itemFrames.first(where: { $0.value.contains(location) }) {
                    handleItemClick(id: itemID)
                }
            }
        }
        .onReceive(gestureManager.longPressOccurred) { location in
            guard !isJiggleMode, openedFolder == nil, let (itemID, _) = itemFrames.first(where: { $0.value.contains(location) }) else { return }

            if let path = viewModel.findPath(for: itemID) {
                let draggedItem = viewModel.pages[path.page].remove(at: path.item)
                viewModel.draggingItem = draggedItem
                viewModel.dragOriginPath = path
            }
        }
        .onReceive(gestureManager.dragEnded) { location in
            edgeSwipeTimer?.invalidate()
            edgeSwipeTimer = nil
            viewModel.cancelReorderTimer()

            guard let dragged = viewModel.draggingItem else { return }
            viewModel.draggingItem = nil
            handleDrop(of: dragged, at: location)
        }
        .onReceive(gestureManager.$isOptionKeyPressed) { isPressed in
            if !gestureManager.isDraggingItem {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    self.isJiggleMode = isPressed
                }
            }
        }
        .environmentObject(viewModel)
        .alert(viewModel.deleteAlertTitle, isPresented: $viewModel.showingDeleteConfirm, presenting: viewModel.itemToDelete) { _ in
            Button(role: .destructive) { viewModel.confirmDeleteItem() } label: {
                if case .app = viewModel.itemToDelete { Text("Move to Trash") } else { Text("Disband") }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelDeleteItem() }
        } message: { _ in
            Text(viewModel.deleteAlertMessage)
        }
        .onPreferenceChange(FolderFramePreferenceKey.self) { newFrame in
            interceptor.folderFrame = newFrame
        }
        .onChange(of: openedFolder) { _, newValue in
            if newValue == nil {
                interceptor.folderFrame = .zero
            }
        }
    }

    private func handleDragChange(at location: CGPoint) {
        let edgeZoneWidth: CGFloat = 100.0
        let screenWidth = NSScreen.main?.frame.width ?? 0

        if location.x < edgeZoneWidth || location.x > screenWidth - edgeZoneWidth {
            viewModel.cancelReorderTimer()
            viewModel.removeDropPlaceholder()
            viewModel.folderCreationTargetID = nil
            startEdgeSwipeTimer(for: location.x < edgeZoneWidth ? .left : .right)
            return
        } else {
            edgeSwipeTimer?.invalidate()
            edgeSwipeTimer = nil
        }

        guard let (pageIndex, pageFrame) = pageFrames.first(where: { $0.value.contains(location) }) else { return }
        let metrics = gridMetrics

        if let targetItem = viewModel.pages[pageIndex].first(where: { itemFrames[$0.id]?.contains(location) ?? false }) {
            viewModel.cancelReorderTimer()
            viewModel.removeDropPlaceholder()
            viewModel.folderCreationTargetID = targetItem.id

        } else {
            viewModel.folderCreationTargetID = nil

            let gridContentWidth = pageFrame.width - (2 * horizontalPadding)
            let columnHitBoxWidth = gridContentWidth / CGFloat(metrics.columns)
            let gridStartX = pageFrame.minX + horizontalPadding

            guard let firstItemID = viewModel.pages[pageIndex].first(where: { $0.id != viewModel.dropPlaceholderID })?.id, let firstItemFrame = itemFrames[firstItemID] else {
                viewModel.cancelReorderTimer()
                return
            }
            let gridStartY = firstItemFrame.minY
            let rowHitBoxHeight = metrics.itemHeight + metrics.verticalSpacing

            var relativeX = location.x - gridStartX
            var relativeY = location.y - gridStartY

            let totalGridHeight = CGFloat(metrics.rows) * metrics.itemHeight + CGFloat(metrics.rows - 1) * metrics.verticalSpacing
            relativeX = max(0, min(relativeX, gridContentWidth - 1))
            relativeY = max(0, min(relativeY, totalGridHeight - 1))

            let col = Int(floor(relativeX / columnHitBoxWidth))
            let row = Int(floor(relativeY / rowHitBoxHeight))

            let finalCol = max(0, min(col, metrics.columns - 1))
            let finalRow = max(0, min(row, metrics.rows - 1))
            let linearIndex = finalRow * metrics.columns + finalCol

            let targetIndex = min(linearIndex, viewModel.pages[pageIndex].count)

            viewModel.startReorderTimer(at: (pageIndex, targetIndex))
        }
    }

    private func startEdgeSwipeTimer(for direction: SwipeDirection) {
        guard edgeSwipeTimer == nil else { return }
        edgeSwipeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            withAnimation(.spring()) {
                if direction == .left { if viewModel.currentPage > 0 { viewModel.currentPage -= 1 } }
                else { if viewModel.currentPage < viewModel.pages.count - 1 { viewModel.currentPage += 1 } }
            }
            self.edgeSwipeTimer?.invalidate()
            self.edgeSwipeTimer = nil
        }
    }

    private func handleDrop(of draggedItem: LaunchpadPageItem, at location: CGPoint) {
        if let targetID = viewModel.folderCreationTargetID,
           let targetItem = viewModel.pages.flatMap({ $0 }).first(where: { $0.id == targetID }),
           let draggedApp = draggedItem.appItem {

            viewModel.folderCreationTargetID = nil

            switch targetItem {
            case .app:
                viewModel.createFolder(with: draggedApp, on: targetItem)
                return
            case .folder(let folder):
                viewModel.addToFolder(draggedApp, to: folder)
                return
            }
        }

        viewModel.finalizeDrop(of: draggedItem)
    }

    private func handleItemClick(id: String) {
        guard !isJiggleMode else { isJiggleMode = false; return }
        guard let item = viewModel.pages.flatMap({ $0 }).first(where: { $0.id == id }) else { return }
        switch item {
        case .app(let appItem):
            if let app = viewModel.getApp(for: appItem) {
                if NSWorkspace.shared.launchApplication(app.name) {
                    NotificationCenter.default.post(name: .requestCloseLaunchpad, object: nil)
                }
            }
        case .folder(let folderItem):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { openedFolder = folderItem }
        }
    }

    @ViewBuilder
    private func folderDetailView(folder: LaunchpadFolder) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        openedFolder = nil
                    }
                }

            VStack(spacing: 20) {
                Text(folder.name).font(.system(size: 20, weight: .semibold)).foregroundColor(.white).padding(.top, 20)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 25), count: 5), spacing: 25) {
                        ForEach(folder.items) { item in
                            if let app = viewModel.getApp(for: item) {
                                AppIconView(app: app, isHovered: false)
                                    .onTapGesture {
                                        if NSWorkspace.shared.launchApplication(app.name) {
                                            openedFolder = nil
                                            NotificationCenter.default.post(name: .requestCloseLaunchpad, object: nil)
                                        }
                                    }
                                    .onLongPressGesture {
                                        viewModel.beginDragFromFolder(item: item, from: folder.id)
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                            openedFolder = nil
                                        }
                                    }
                            }
                        }
                    }.padding()
                }
            }
            .frame(maxWidth: 700, maxHeight: 500)
            .background(
                GeometryReader { geo in
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .preference(key: FolderFramePreferenceKey.self, value: geo.frame(in: .global))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 20)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var paginatedView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { pageIndex, page in
                    appGridView(for: page)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, bottomPadding)
                        .frame(width: geometry.size.width)
                        .background(
                            GeometryReader { pageGeo in
                                Color.clear
                                    .onAppear { self.pageFrames[pageIndex] = pageGeo.frame(in: .global) }
                                    .onChange(of: pageGeo.frame(in: .global)) { _, newFrame in self.pageFrames[pageIndex] = newFrame }
                            }
                        )
                }
            }
            .offset(x: (CGFloat(viewModel.currentPage) * -geometry.size.width) + gestureManager.dragOffset)
            .onPreferenceChange(ItemFramePreferenceKey.self) { value in self.itemFrames = value }
            .onChange(of: gestureManager.isPageSwiping) { _, isSwiping in
                if !isSwiping {
                    let flickThreshold: CGFloat = 100; let dragThreshold = geometry.size.width / 4; var newPage = viewModel.currentPage
                    if gestureManager.dragOffset > dragThreshold || gestureManager.dragOffset > flickThreshold { if viewModel.currentPage > 0 { newPage -= 1 } }
                    else if gestureManager.dragOffset < -dragThreshold || gestureManager.dragOffset < -flickThreshold { if viewModel.currentPage < viewModel.pages.count - 1 { newPage += 1 } }
                    withAnimation(.spring()) { viewModel.currentPage = newPage; gestureManager.resetDragOffset() }
                }
            }
        }.clipped()
    }

    @ViewBuilder
    private var searchResultsView: some View {
        ScrollView {
            VStack {
                LazyVGrid(columns: columns, spacing: gridMetrics.verticalSpacing) {
                    ForEach(viewModel.filteredApps) { app in
                        AppIconView(app: app, isHovered: false)
                            .onTapGesture {
                                if NSWorkspace.shared.launchApplication(app.name) {
                                    NotificationCenter.default.post(name: .requestCloseLaunchpad, object: nil)
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 30 + bottomPadding)
        }
    }

    @ViewBuilder
    private func appGridView(for page: [LaunchpadPageItem]) -> some View {
        VStack {
            Spacer()
            LazyVGrid(columns: columns, spacing: gridMetrics.verticalSpacing) {
                ForEach(page) { item in
                    if item.id == viewModel.dropPlaceholderID {
                        Rectangle().fill(Color.blue.opacity(0.3)).frame(width: gridMetrics.itemWidth, height: gridMetrics.itemHeight).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 2).opacity(0.7))
                    } else {
                        LaunchpadItemView(
                            item: item,
                            isHovered: item.id == hoveredItemID,
                            isJiggling: isJiggleMode,
                            isFolderTarget: item.id == viewModel.folderCreationTargetID
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: ItemFramePreferenceKey.self, value: [item.id: geo.frame(in: .global)])
                            }
                        )
                    }
                }
            }
            Spacer()
        }
        .animation(.default, value: page.map(\.id))
        .animation(.default, value: isJiggleMode)
    }

    private var paginationDots: some View {
        HStack(spacing: 12) {
            ForEach(0..<viewModel.pages.count, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == viewModel.currentPage ? 0.8 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(.spring(), value: viewModel.currentPage)
                    .onTapGesture { withAnimation(.spring()) { viewModel.currentPage = index } }
            }
        }
    }
}

// MARK: - Helper Extensions
extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
extension CGPoint { func distanceTo(_ point: CGPoint) -> CGFloat { sqrt(pow(self.x - point.x, 2) + pow(self.y - point.y, 2)) } }