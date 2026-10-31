import SwiftUI

struct AccountProfileView: View {
    let account: AuthAccount
    let openLibrary: (String) -> Void
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.collection) private var collection
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ProfileHeader(
                            name: "Shogun account", email: account.email, badge: "Signed in")
                    }.listRowBackground(ShogunTheme.canvas)
                    if let collection {
                        CollectionProfileSection(store: collection, openLibrary: openLibrary)
                    } else {
                        Section("Your personal library") {
                            Label(account.libraryName, systemImage: "person").badge("Personal")
                        }
                    }
                    Section {
                        NavigationLink("About & credits") { ShogunAboutView() }
                    }
                    Section {
                        if let error = auth.error {
                            Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                                "auth.error")
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

                }.listRowBackground(ShogunTheme.surface)
            }.navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar).scrollContentBackground(.hidden).background(
                    ShogunTheme.canvas
                )
                .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
    }
}

private struct CollectionProfileSection: View {
    @ObservedObject var store: CollectionStore
    let openLibrary: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var libraries: [MovieLibrary] {
        let all = store.catalog?.libraries ?? []
        return all.filter { $0.id == store.defaultLibraryID }
            + all.filter { $0.id != store.defaultLibraryID }
    }
    var body: some View {
        Section {
            ForEach(Array(libraries.prefix(3))) { library in
                Button {
                    openLibrary(library.id)
                } label: {
                    LibraryProfileRow(
                        library: library, isDefault: library.id == store.defaultLibraryID)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open this library")
                .accessibilityIdentifier("profile.openLibrary.\(library.id)")
            }
            if libraries.isEmpty {
                Text("No libraries yet").foregroundStyle(ShogunTheme.muted)
            }
            if libraries.count > 3 {
                NavigationLink("See all libraries") { LibraryPreferencesView(store: store) }
            }
        } header: {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
                    Text("Libraries")
                    manageLink
                }
            } else {
                HStack {
                    Text("Libraries")
                    Spacer()
                    manageLink
                }
            }
        }
    }
    private var manageLink: some View {
        NavigationLink("Manage") { LibraryPreferencesView(store: store) }
            .frame(minHeight: ShogunTheme.Size.touchTarget)
            .textCase(nil)
            .accessibilityLabel("Manage libraries")
            .accessibilityIdentifier("profile.manageLibraries")
    }
}

private struct LibraryProfileRow: View {
    let library: MovieLibrary
    let isDefault: Bool
    var body: some View {
        HStack(spacing: ShogunTheme.Spacing.control) {
            Image(systemName: library.isShared ? "person.2.fill" : "film.stack.fill")
                .font(ShogunTheme.Typography.viewIcon)
                .foregroundStyle(ShogunTheme.muted)
                .frame(width: ShogunTheme.Size.touchTarget, height: ShogunTheme.Size.touchTarget)
                .background(
                    ShogunTheme.raised,
                    in: RoundedRectangle(cornerRadius: ShogunTheme.Radius.poster)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.tight) {
                Text(library.name).font(ShogunTheme.Typography.emphasizedBody)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(
                    isDefault
                        ? "Default library"
                        : (library.isShared ? "Shared library" : "Personal library")
                )
                .font(ShogunTheme.Typography.caption).foregroundStyle(ShogunTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryPreferencesView: View {
    @ObservedObject var store: CollectionStore
    @State private var creatingLibrary = false
    var body: some View {
        List {
            Group {
                Section {
                    ForEach(store.catalog?.libraries ?? []) { library in
                        Button {
                            Task { _ = await store.setDefault(libraryID: library.id) }
                        } label: {
                            HStack(spacing: ShogunTheme.Spacing.control) {
                                LibraryProfileRow(
                                    library: library,
                                    isDefault: library.id == store.defaultLibraryID)
                                if library.id == store.defaultLibraryID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ShogunTheme.accent).accessibilityHidden(
                                            true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            store.isBusy
                                || store.catalog?.writableLibraries.contains(where: {
                                    $0.id == library.id
                                }) != true
                        )
                        .accessibilityLabel(library.name)
                        .accessibilityValue(
                            library.id == store.defaultLibraryID
                                ? "Default library"
                                : (store.catalog?.writableLibraries.contains(where: {
                                    $0.id == library.id
                                }) == true ? "Select as default" : "Read only")
                        )
                        .accessibilityIdentifier("profile.defaultLibrary.\(library.id)")
                    }
                } header: {
                    Text("Default library")
                } footer: {
                    Text(
                        "Choose the library selected when you open your collection. Only libraries you can add movies to can be the default."
                    )
                }
                Section {
                    Button("Create library") { creatingLibrary = true }
                        .disabled(store.isBusy)
                    CollectionFeedback(store: store)
                }
            }.listRowBackground(ShogunTheme.surface)
        }
        .shogunListCanvas()
        .navigationTitle("Manage libraries")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingLibrary) { CreateLibrarySheet() }
    }
}

private struct ShogunAboutView: View {
    var body: some View {
        List {
            Group {
                Section("Shogun") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.object(
                            forInfoDictionaryKey: "ShogunDisplayVersion") as? String
                            ?? Bundle.main.object(
                                forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? "—")
                }
                Section("Movie information") { TMDBAttributionView() }
            }.listRowBackground(ShogunTheme.surface)
        }
        .shogunListCanvas()
        .navigationTitle("About & credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
