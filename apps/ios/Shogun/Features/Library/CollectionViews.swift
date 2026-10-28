import SwiftUI

private struct CollectionEnvironmentKey: EnvironmentKey {
    static let defaultValue: CollectionStore? = nil
}
extension EnvironmentValues {
    var collection: CollectionStore? {
        get { self[CollectionEnvironmentKey.self] }
        set { self[CollectionEnvironmentKey.self] = newValue }
    }
}

struct ConnectedCollectionTabs: View {
    let account: AuthAccount
    @StateObject private var collection: CollectionStore
    @StateObject private var search: CatalogSearchStore
    private let discovery: any MovieDiscoveryServicing
    init(account: AuthAccount, services: AccountServices) {
        self.account = account
        self.discovery = services.discovery
        _search = StateObject(wrappedValue: CatalogSearchStore(service: services.discovery))
        _collection = StateObject(
            wrappedValue: CollectionStore(userID: account.id, service: services.collection))
    }
    var body: some View {
        TabView {
            Group {
                if let catalog = collection.catalog, !catalog.libraries.isEmpty {
                    LibraryView().environmentObject(catalog)
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
            }.tabItem { Label("Library", systemImage: "square.grid.2x2") }
            CatalogSearchView(search: search, collection: collection, service: discovery)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            AccountProfileView(account: account).tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
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
    var body: some View {
        VStack(spacing: ShogunTheme.Spacing.small) {
            if let error = store.error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("collection.error")
            }
            Button("Refresh collection") { Task { await store.refresh() } }
                .disabled(store.isBusy).accessibilityIdentifier("collection.refresh")
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
                TextField("Library name", text: $name).accessibilityIdentifier(
                    "collection.libraryName"
                )
                .onChange(of: name) { _, _ in requestID = UUID().uuidString }
                Text(
                    "Creates a shared library owned by your account. Invitations are managed separately."
                )
                .font(ShogunTheme.Typography.footnote)
                CollectionFeedback(store: collection)
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
