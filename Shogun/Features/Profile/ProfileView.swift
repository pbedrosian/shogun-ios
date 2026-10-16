import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: CatalogStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(.tint)
                        Text("Alex Morgan").font(.title2.bold())
                        Text("alex@example.com").foregroundStyle(.secondary)
                        Text("Demo account").font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary, in: Capsule())
                    }.frame(maxWidth: .infinity).padding(.vertical)
                }
                Section("Your libraries") {
                    ForEach(store.libraries) { library in Label(library.name, systemImage: library.isShared ? "person.2" : "person").badge(library.isShared ? "Shared" : "Personal") }
                }
                Section("About this preview") {
                    LabeledContent("Version", value: "1.0 · Phase 1")
                    Text("Apple, Google, and email sign-in, family invitations, and online movie lookup are planned for future phases.").font(.subheadline).foregroundStyle(.secondary)
                    Text("All content is local sample data. No account is connected.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Profile")
        }
    }
}
