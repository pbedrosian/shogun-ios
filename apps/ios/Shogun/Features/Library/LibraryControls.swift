import SwiftUI

struct LibraryHeaderControls: View {
    @EnvironmentObject private var store: CatalogStore
    let onInteraction: () -> Void
    let canAdd: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: ShogunTheme.Spacing.compact) {
            ShogunWordmark()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("library.brand")
            HStack(alignment: .center, spacing: ShogunTheme.Spacing.tight) {
                Text((store.selectedLibrary?.name ?? "Libraries")).font(
                    ShogunTheme.Typography.title
                )
                .lineLimit(2).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                LibraryViewOptions(onInteraction: onInteraction)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0)
                            .onChanged { _ in onInteraction() })
                if canAdd {
                    Button {
                        onInteraction()
                        store.showingAddMovie = true
                    } label: {
                        ShogunIcon(systemName: "plus")
                    }.accessibilityLabel("Add movie").disabled(
                        store.writableLibraries.isEmpty)
                }
            }
        }
    }

}

struct LibrarySelectorControl: View {
    @EnvironmentObject private var store: CatalogStore
    let onInteraction: () -> Void
    var body: some View {
        Menu {
            Picker("Library", selection: $store.selectedLibraryID) {
                ForEach(store.libraries) {
                    Text($0.name).lineLimit(1).truncationMode(.tail).tag($0.id)
                }
            }
        } label: {
            HStack {
                Image(
                    systemName: (store.selectedLibrary?.isShared ?? false)
                        ? "person.2" : "person")
                Text((store.selectedLibrary?.name ?? "Libraries")).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.down").font(
                    ShogunTheme.Typography.disclosure)
            }.font(ShogunTheme.Typography.body).foregroundStyle(ShogunTheme.ink)
                .shogunSurface(padding: ShogunTheme.Spacing.selector)
        }.accessibilityLabel(
            "Select library, \((store.selectedLibrary?.name ?? "Libraries"))"
        ).accessibilityIdentifier("library.selector")
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0)
                    .onChanged { _ in onInteraction() })
    }

}

struct LibrarySearchControl: View {
    @EnvironmentObject private var store: CatalogStore
    let onInteraction: () -> Void
    var body: some View {
        HStack(spacing: ShogunTheme.Spacing.medium) {
            Image(systemName: "magnifyingglass").foregroundStyle(ShogunTheme.muted)
            TextField("Search this library", text: $store.libraryQuery).font(
                ShogunTheme.Typography.body
            ).autocorrectionDisabled()
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0)
                        .onChanged { _ in onInteraction() })
            if !store.libraryQuery.isEmpty {
                Button {
                    onInteraction()
                    store.libraryQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }.accessibilityLabel("Clear search")
            }
        }.shogunSurface()
    }

}

struct LibraryFilterSummary: View {
    @EnvironmentObject private var store: CatalogStore
    let onInteraction: () -> Void
    @Environment(\.collection) private var collection
    let movieCount: Int
    var body: some View {
        Text("\(movieCount) \(movieCount == 1 ? "movie" : "movies")")
            .font(ShogunTheme.Typography.caption).foregroundStyle(ShogunTheme.muted)
        if !store.libraryFormats.isEmpty {
            HStack {
                Text(
                    MovieFormat.allCases.filter { store.libraryFormats.contains($0) }
                        .map(\.rawValue).joined(separator: " · ")
                )
                .font(ShogunTheme.Typography.caption)
                .foregroundStyle(ShogunTheme.muted)
                Spacer()
                Button("Clear filters") {
                    onInteraction()
                    store.libraryFormats.removeAll()
                }
            }
        }
        if let collection {
            CollectionFeedback(store: collection, showsRefreshButton: false)
        }
    }

}

private struct LibraryViewOptions: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onInteraction: () -> Void
    private var columnCount: Int { typeSize.isAccessibilitySize ? 2 : store.libraryColumns }
    var body: some View {
        Menu {
            Section("Sort") {
                ForEach(LibrarySort.allCases) { sort in
                    Button {
                        store.selectLibrarySort(sort)
                    } label: {
                        if store.librarySort == sort {
                            Label(sort.rawValue, systemImage: "checkmark")
                        } else {
                            Text(sort.rawValue)
                        }
                    }.accessibilityValue(store.librarySort == sort ? "Selected" : "Not selected")
                        .menuActionDismissBehavior(.disabled)
                }
            }
            Menu("Formats", systemImage: "opticaldisc") {
                ForEach(MovieFormat.allCases) { format in
                    Toggle(
                        format.rawValue,
                        isOn: Binding(
                            get: { store.libraryFormats.contains(format) },
                            set: { selected in
                                if selected {
                                    store.libraryFormats.insert(format)
                                } else {
                                    store.libraryFormats.remove(format)
                                }
                            })
                    )
                    .accessibilityValue(
                        store.libraryFormats.contains(format) ? "Selected" : "Not selected"
                    )
                    .menuActionDismissBehavior(.disabled)
                }
                Button("Clear filters") {
                    onInteraction()
                    store.libraryFormats.removeAll()
                }
                .disabled(store.libraryFormats.isEmpty)
                .menuActionDismissBehavior(.disabled)
            }
            Menu("View Options", systemImage: "square.grid.2x2") {
                Button {
                    withAnimation(reduceMotion ? nil : .default) { store.zoomIn() }
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }.disabled(store.libraryColumns <= 2 || typeSize.isAccessibilitySize)
                    .menuActionDismissBehavior(.disabled)
                Button {
                    withAnimation(reduceMotion ? nil : .default) { store.zoomOut() }
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }.disabled(store.libraryColumns >= 5 || typeSize.isAccessibilitySize)
                    .menuActionDismissBehavior(.disabled)
                Text(
                    typeSize.isAccessibilitySize
                        ? "2 columns for larger text" : "\(store.libraryColumns) posters per row")
            }
        } label: {
            ShogunIcon(
                systemName: "line.3.horizontal.decrease",
                font: ShogunTheme.Typography.viewIcon)
        }.menuActionDismissBehavior(.disabled)
            .accessibilityLabel("Library view options")
            .accessibilityIdentifier("library.viewOptions")
            .accessibilityValue("\(columnCount)")
    }
}
