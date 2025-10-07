//
//  AppIconView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
class LaunchpadViewModel: ObservableObject {
    @Published var pages: [[SystemApp]] = []
    @Published var currentPage: Int = 0
    @Published var searchText: String = ""
    @Published var filteredApps: [SystemApp] = []

    private let appsPerPage = 35
    private var allApps: [SystemApp] = []
    private let appFetcher = SystemAppFetcher()
    private var cancellables = Set<AnyCancellable>()

    init() {
        appFetcher.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.allApps = apps
                self?.paginateApps(apps)
            }
            .store(in: &cancellables)

        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.filterApps(with: text)
            }
            .store(in: &cancellables)
    }

    func fetchApps() {
        appFetcher.fetchApps()
    }

    private func paginateApps(_ apps: [SystemApp]) {
        self.pages = stride(from: 0, to: apps.count, by: appsPerPage).map {
            Array(apps[$0..<min($0 + appsPerPage, apps.count)])
        }
    }

    private func filterApps(with query: String) {
        if query.isEmpty {
            filteredApps = []
        } else {
            filteredApps = allApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }
}

// MARK: - Search Bar View

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))
                .font(.system(size: 15, weight: .semibold))

            ZStack(alignment: .leading) {
                Text("Search")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.system(size: 16, weight: .regular))
                    .opacity(text.isEmpty && !isFocused ? 1 : 0)

                TextField("", text: $text)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .regular))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(width: 250)
        .onTapGesture {
            isFocused = true
        }
    }
}

// MARK: - App Icon View

struct AppIconView: View {
    let app: SystemApp
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)

            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .frame(maxWidth: 100)
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Launchpad View

struct LaunchpadView: View {
    @StateObject private var viewModel = LaunchpadViewModel()
    @Binding var isVisible: Bool

    @State private var dragOffset: CGFloat = .zero

    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 35), count: 7)

    var body: some View {
        ZStack {
            VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()
                .onTapGesture {
                    isVisible = false
                }

            VStack(spacing: 0) {
                SearchBar(text: $viewModel.searchText)
                    .padding(.top, 40)

                if viewModel.searchText.isEmpty {
                    paginatedView
                } else {
                    searchResultsView
                }
            }

            if viewModel.searchText.isEmpty && viewModel.pages.count > 1 {
                VStack {
                    Spacer()
                    paginationDots
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear(perform: viewModel.fetchApps)
        .onExitCommand {
            isVisible = false
        }
    }

    @ViewBuilder
    private var paginatedView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(viewModel.pages.indices, id: \.self) { pageIndex in
                    appGridView(for: viewModel.pages[pageIndex])
                        .frame(width: geometry.size.width)
                }
            }
            .offset(x: (CGFloat(viewModel.currentPage) * -geometry.size.width) + dragOffset)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: viewModel.currentPage)
            .gesture(
                DragGesture()
                    .onChanged { self.dragOffset = $0.translation.width }
                    .onEnded { value in
                        let threshold: CGFloat = 50
                        if value.predictedEndTranslation.width < -threshold, viewModel.currentPage < viewModel.pages.count - 1 {
                            viewModel.currentPage += 1
                        } else if value.predictedEndTranslation.width > threshold, viewModel.currentPage > 0 {
                            viewModel.currentPage -= 1
                        }

                        withAnimation(.spring()) {
                            self.dragOffset = .zero
                        }
                    }
            )
        }
        .clipped()
        .padding(.horizontal, 180)
    }

    @ViewBuilder
    private var searchResultsView: some View {
        ScrollView {
            appGridView(for: viewModel.filteredApps)
        }
        .padding(.horizontal, 180)
        .padding(.bottom, 30)
    }

    @ViewBuilder
    private func appGridView(for apps: [SystemApp]) -> some View {
        VStack {
            Spacer()
            LazyVGrid(columns: columns, spacing: 35) {
                ForEach(apps) { app in
                    Button(action: {
                        if NSWorkspace.shared.launchApplication(app.name) {
                            isVisible = false
                        }
                    }) {
                        AppIconView(app: app)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    private var paginationDots: some View {
        HStack(spacing: 12) {
            ForEach(0..<viewModel.pages.count, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == viewModel.currentPage ? 0.8 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: viewModel.currentPage)
            }
        }
    }
}