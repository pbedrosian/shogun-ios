import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.collection) private var collection
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isArranging = false
    @State private var navigationPath: [Movie] = []
    @State private var draggedMovieID: String?
    @State private var lastDropTargetID: String?
    @State private var dragLocation: CGPoint?
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var pinchStartingColumns: Int?
    @GestureState private var isPinching = false
    private var columnCount: Int { typeSize.isAccessibilitySize ? 2 : store.libraryColumns }
    private var movies: [Movie] { store.libraryResults }
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.section) {
                    LibraryHeaderControls(onInteraction: finishArranging, canAdd: collection != nil)
                    LibrarySelectorControl(onInteraction: finishArranging)
                    LibrarySearchControl(onInteraction: finishArranging)
                    LibraryFilterSummary(onInteraction: finishArranging, movieCount: movies.count)
                    libraryGrid
                }.padding(.horizontal, ShogunTheme.Spacing.screen).padding(
                    .top, ShogunTheme.Spacing.regular
                ).padding(.bottom, ShogunTheme.Spacing.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("library.scroll")
            .contentShape(Rectangle())
            .highPriorityGesture(
                MagnifyGesture(minimumScaleDelta: 0.01)
                    .updating($isPinching) { _, active, _ in active = true }
                    .onChanged { value in
                        guard !typeSize.isAccessibilitySize else { return }
                        let startingColumns = pinchStartingColumns ?? store.libraryColumns
                        pinchStartingColumns = startingColumns
                        withAnimation(
                            reduceMotion
                                ? nil : .interactiveSpring(response: 0.2, dampingFraction: 0.9)
                        ) {
                            store.updateLibraryPinch(
                                magnification: Double(value.magnification),
                                startingColumns: startingColumns)
                        }
                    }
                    .onEnded { _ in pinchStartingColumns = nil },
                including: typeSize.isAccessibilitySize ? .subviews : .all
            )
            .coordinateSpace(name: "library.grid")
            .onPreferenceChange(MovieGridFrames.self) { tileFrames = $0 }
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named("library.grid"))
                    .onEnded { tap in
                        if isArranging
                            && !tileFrames.values.contains(where: { $0.contains(tap.location) })
                        {
                            finishArranging()
                        }
                    },
                including: isArranging ? .all : .subviews
            )
            .onChange(of: isPinching) { _, active in
                if !active { pinchStartingColumns = nil }
            }
            .onChange(of: store.selectedLibraryID) { _, _ in finishArranging() }
            .onChange(of: store.librarySort) { _, sort in
                if sort != .custom { finishArranging() }
            }
            .onDisappear { finishArranging() }
            .refreshable { await collection?.refresh() }
            .shogunCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(isArranging ? .hidden : .visible, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if isArranging {
                    Button(action: finishArranging) {
                        Text("Done")
                            .frame(maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ShogunTheme.primaryAction)
                    .foregroundStyle(ShogunTheme.onPrimaryAction)
                    .accessibilityIdentifier("library.arrange.done")
                    .padding(.horizontal, ShogunTheme.Spacing.screen)
                    .padding(.vertical, ShogunTheme.Spacing.control)
                    .background(ShogunTheme.canvas)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie).toolbar(.visible, for: .navigationBar)
            }
            .sheet(isPresented: $store.showingAddMovie) { LibraryAddMovieSheet() }
        }
    }
    @ViewBuilder private var libraryGrid: some View {
        if movies.isEmpty {
            if !store.libraryFormats.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No matching movies", systemImage: "line.3.horizontal.decrease")
                } description: {
                    Text("Try another format or clear filters to see more movies.")
                } actions: {
                    Button("Clear filters") {
                        finishArranging()
                        store.libraryFormats.removeAll()
                    }
                }
            } else if store.libraryQuery.isEmpty {
                ContentUnavailableView(
                    "No movies yet", systemImage: "film.stack",
                    description: Text("Add a copy from your available movie catalog."))
            } else {
                ContentUnavailableView.search(text: store.libraryQuery)
            }
        } else {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .flexible(), spacing: ShogunTheme.Spacing.small, alignment: .top
                    ), count: columnCount), alignment: .leading,
                spacing: ShogunTheme.Spacing.regular
            ) {
                ForEach(movies) { movie in
                    LibraryMovieTile(
                        movie: movie, compact: columnCount >= 4,
                        formatDescription: MovieFormat.allCases.filter { format in
                            store.copies(for: movie, libraryID: store.selectedLibraryID).contains {
                                $0.format == format
                            }
                        }.map(\.rawValue).joined(separator: " · "),
                        isCustom: store.librarySort == .custom, isArranging: isArranging,
                        isPinching: isPinching, isDragging: draggedMovieID == movie.id,
                        dragOffset: dragOffset(for: movie.id),
                        onBegin: beginArranging, onNavigate: { navigationPath.append(movie) },
                        onDragChanged: { moveDraggedMovie(movie.id, over: $0) },
                        onDragEnded: endDragging,
                        onMoveOffset: { store.moveCustomMovie(movie.id, by: $0) }
                    )
                    .zIndex(draggedMovieID == movie.id ? 1 : 0)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MovieGridFrames.self,
                                value: [
                                    movie.id: proxy.frame(
                                        in: .named("library.grid"))
                                ])
                        }
                    }
                }
            }

        }
    }

    private func dragOffset(for movieID: String) -> CGSize {
        guard draggedMovieID == movieID, let point = dragLocation, let frame = tileFrames[movieID]
        else { return .zero }
        return CGSize(width: point.x - frame.midX, height: point.y - frame.midY)
    }
    private func moveDraggedMovie(_ movieID: String, over point: CGPoint) {
        guard isArranging, store.librarySort == .custom else { return }
        if draggedMovieID != movieID { lastDropTargetID = nil }
        draggedMovieID = movieID
        dragLocation = point
        guard let target = tileFrames.first(where: { $0.value.contains(point) })?.key else {
            return
        }
        if target == movieID {
            lastDropTargetID = nil
            return
        }
        guard lastDropTargetID != target else { return }
        lastDropTargetID = target
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            store.moveCustomMovie(movieID, to: target)
        }
    }
    private func endDragging() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { clearDrag() }
    }
    private func clearDrag() {
        draggedMovieID = nil
        dragLocation = nil
        lastDropTargetID = nil
    }
    private func beginArranging() {
        guard store.librarySort == .custom, !isArranging, !isPinching else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            isArranging = true
        }
    }
    private func finishArranging() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            isArranging = false
            clearDrag()
        }
    }

}

private struct MovieGridFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
