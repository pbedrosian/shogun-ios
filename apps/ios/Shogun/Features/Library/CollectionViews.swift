import SwiftUI

private struct CollectionEnvironmentKey: EnvironmentKey {
    static let defaultValue: CollectionStore? = nil
}
private struct MovieDiscoveryEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any MovieDiscoveryServicing)? = nil
}
extension EnvironmentValues {
    var movieDiscovery: (any MovieDiscoveryServicing)? {
        get { self[MovieDiscoveryEnvironmentKey.self] }
        set { self[MovieDiscoveryEnvironmentKey.self] = newValue }
    }
    var collection: CollectionStore? {
        get { self[CollectionEnvironmentKey.self] }
        set { self[CollectionEnvironmentKey.self] = newValue }
    }
}

struct ConnectedCollectionTabs: View {
    let account: AuthAccount
    @StateObject private var collection: CollectionStore
    @StateObject private var search: CatalogSearchStore
    @State private var selectedTab: ShogunTab = .library
    @State private var libraryNavigationID = UUID()
    private let discovery: any MovieDiscoveryServicing
    init(account: AuthAccount, services: AccountServices) {
        self.account = account
        self.discovery = services.discovery
        _search = StateObject(wrappedValue: CatalogSearchStore(service: services.discovery))
        _collection = StateObject(
            wrappedValue: CollectionStore(userID: account.id, service: services.collection))
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if let catalog = collection.catalog, !catalog.libraries.isEmpty {
                    LibraryView().id(libraryNavigationID).environmentObject(catalog)
                } else {
                    NavigationStack {
                        VStack(spacing: ShogunTheme.Spacing.regular) {
                            if collection.isBusy {
                                ProgressView("Loading your collection…")
                            } else if collection.error == nil {
                                ContentUnavailableView(
                                    "No libraries", systemImage: "film.stack",
                                    description: Text(
                                        "Create your personal library to get started."))
                                Button("Create personal library") {
                                    Task { _ = await collection.restorePersonalLibrary() }
                                }
                            }
                            CollectionFeedback(store: collection)
                        }.shogunCanvas().navigationTitle("Library")
                    }
                }
            }.tabItem { Label("Library", systemImage: "square.grid.2x2") }.tag(ShogunTab.library)
            CatalogSearchView(search: search, collection: collection, service: discovery)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(ShogunTab.search)
            AccountProfileView(account: account) { libraryID in
                guard let catalog = collection.catalog,
                    catalog.libraries.contains(where: { $0.id == libraryID })
                else { return }
                catalog.selectedLibraryID = libraryID
                catalog.libraryQuery = ""
                catalog.showingAddMovie = false
                libraryNavigationID = UUID()
                selectedTab = .library
            }.tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }.tag(ShogunTab.profile)
        }
        .environment(\.movieDiscovery, discovery)
        .environment(\.collection, collection)
        .environmentObject(collection)
        .task { await collection.refresh() }
        .onDisappear {
            collection.invalidate()
            search.invalidate()
        }
    }
}

struct CollectionFeedback: View {
    @ObservedObject var store: CollectionStore
    var showsRefreshButton = true
    var body: some View {
        VStack(spacing: ShogunTheme.Spacing.small) {
            if let error = store.error {
                Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                    "collection.error")
            }
            if showsRefreshButton {
                Button("Refresh collection") { Task { await store.refresh() } }
                    .disabled(store.isBusy).accessibilityIdentifier("collection.refresh")
            }
            if store.isBusy { ProgressView().accessibilityLabel("Updating collection") }
        }
    }
}

struct CreateLibrarySheet: View {
    @EnvironmentObject private var collection: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var requestID = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    TextField("Library name", text: $name).accessibilityIdentifier(
                        "collection.libraryName"
                    )
                    .onChange(of: name) { _, _ in requestID = UUID().uuidString }
                    Text(
                        "Creates a shared library owned by your account. Invitations are managed separately."
                    )
                    .font(ShogunTheme.Typography.footnote)
                    CollectionFeedback(store: collection)

                }.listRowBackground(ShogunTheme.surface)
            }.shogunListCanvas().navigationTitle("Create library")
                .interactiveDismissDisabled(collection.isBusy)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(collection.isBusy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task {
                                if await collection.createLibrary(id: requestID, name: name) {
                                    dismiss()
                                }
                            }
                        }.disabled(
                            collection.isBusy
                                || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
