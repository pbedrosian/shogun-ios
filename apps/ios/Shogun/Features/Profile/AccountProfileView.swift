import SwiftUI

struct AccountProfileView: View {
    let account: AuthAccount
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.collection) private var collection
    @State private var creatingLibrary = false
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProfileHeader(name: "Shogun account", email: account.email, badge: "Signed in")
                }
                if let collection {
                    CollectionProfileSection(store: collection, creatingLibrary: $creatingLibrary)
                } else {
                    Section("Your personal library") {
                        Label(account.libraryName, systemImage: "person").badge("Personal")
                    }
                }
                Section("Movie information") { TMDBAttributionView() }
                Section("About") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
                Section {
                    if let error = auth.error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.error")
                    }
                    Button("Sign out", role: .destructive, action: auth.signOut).disabled(
                        auth.isBusy
                    ).accessibilityIdentifier("auth.signOut")
                    Button("Delete account", role: .destructive) {
                        auth.clearFeedback()
                        deleting = true
                    }
                    .disabled(auth.isBusy).accessibilityIdentifier("auth.deleteAccount")
                }
            }.navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar).scrollContentBackground(.hidden).background(
                    ShogunTheme.canvas
                )
                .sheet(isPresented: $creatingLibrary) { CreateLibrarySheet() }
                .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
    }
}

private struct CollectionProfileSection: View {
    @ObservedObject var store: CollectionStore
    @Binding var creatingLibrary: Bool
    var body: some View {
        Section("Your libraries") {
            ForEach(store.catalog?.libraries ?? []) { library in
                VStack(alignment: .leading) {
                    Label(library.name, systemImage: library.isShared ? "person.2" : "person")
                    if store.defaultLibraryID == library.id {
                        Text("Default library").font(ShogunTheme.Typography.caption)
                    } else if store.catalog?.writableLibraries.contains(where: {
                        $0.id == library.id
                    }) == true {
                        Button("Use \(library.name) by default") {
                            Task { _ = await store.setDefault(libraryID: library.id) }
                        }
                        .disabled(store.isBusy)
                    }
                }
            }
            Button("Create library") { creatingLibrary = true }.disabled(store.isBusy)
            CollectionFeedback(store: store)
        }
    }
}
