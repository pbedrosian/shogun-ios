import SwiftUI

#if DEBUG
    struct ProfileView: View {
        let openLibrary: (String) -> Void
        @EnvironmentObject private var store: CatalogStore
        @EnvironmentObject private var auth: AuthStore
        var body: some View {
            NavigationStack {
                List {
                    Group {
                        Section {
                            ProfileHeader(
                                name: "Alex Morgan", email: "alex@example.com",
                                badge: "Demo account")
                        }
                        Section {
                            Button("Leave demo", action: auth.leaveDemo).accessibilityIdentifier(
                                "auth.leaveDemo")
                        }
                        Section("Your libraries") {
                            ForEach(store.libraries) { library in
                                Button {
                                    openLibrary(library.id)
                                } label: {
                                    Label(
                                        library.name,
                                        systemImage: library.isShared ? "person.2" : "person")
                                }
                                .accessibilityIdentifier("profile.openLibrary.\(library.id)")
                            }
                        }
                        Section("About this preview") {
                            LabeledContent("Version", value: "1.0 · Phase 1")
                            Text(
                                "This demo stays offline. Leave demo to connect your real account with email sign-in. Family invitations and online movie lookup are coming later."
                            ).font(ShogunTheme.Typography.body).foregroundStyle(ShogunTheme.muted)
                            Text("All content is local sample data. No account is connected.").font(
                                ShogunTheme.Typography.footnote
                            ).foregroundStyle(ShogunTheme.muted)
                        }

                    }.listRowBackground(ShogunTheme.surface)
                }.shogunListCanvas().navigationTitle(
                    "Profile"
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
            }
        }
    }
#endif
