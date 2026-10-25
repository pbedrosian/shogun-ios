import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: CatalogStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: ShogunTheme.Spacing.medium) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(.tint)
                        Text("Alex Morgan").font(ShogunTheme.Typography.profileTitle)
                        Text("alex@example.com").foregroundStyle(.secondary)
                        Text("Demo account").font(ShogunTheme.Typography.disclosure).padding(.horizontal, ShogunTheme.Spacing.control).padding(.vertical, ShogunTheme.Spacing.compact).background(.quaternary, in: Capsule())
                    }.frame(maxWidth: .infinity).padding(.vertical)
                }
                Section("Your libraries") {
                    ForEach(store.libraries) { library in Label(library.name, systemImage: library.isShared ? "person.2" : "person").badge(library.isShared ? "Shared" : "Personal") }
                }
                Section("About this preview") {
                    LabeledContent("Version", value: "1.0 · Phase 1")
                    Text("Apple, Google, and email sign-in, family invitations, and online movie lookup are planned for future phases.").font(ShogunTheme.Typography.body).foregroundStyle(.secondary)
                    Text("All content is local sample data. No account is connected.").font(ShogunTheme.Typography.footnote).foregroundStyle(.secondary)
                }
            }.scrollContentBackground(.hidden).background(ShogunTheme.canvas).navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        }
    }
}
