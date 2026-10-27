import SwiftUI

struct AuthRootView: View {
    @EnvironmentObject private var auth: AuthStore
    var body: some View {
        Group {
            #if DEBUG
                if auth.isDemo { DemoTabs().id("offline-demo") } else { accountContent }
            #else
                accountContent
            #endif
        }
        .tint(ShogunTheme.accent)
        .task { auth.start() }
        .onOpenURL { auth.handle($0) }
    }
    @ViewBuilder private var accountContent: some View {
        if auth.isRestoring {
            VStack(spacing: ShogunTheme.Spacing.regular) {
                ProgressView("Restoring your session…")
                Button("Cancel", action: auth.cancel)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).shogunCanvas()
        } else if auth.needsPasswordUpdate {
            PasswordUpdateView()
        } else if let account = auth.account {
            AccountTabs(account: account).id(account.id)
        } else {
            AuthFormView()
        }
    }
}

#if DEBUG
    private struct DemoTabs: View {
        @StateObject private var catalog = CatalogStore()
        var body: some View {
            TabView {
                LibraryView().tabItem { Label("Library", systemImage: "square.grid.2x2") }
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
                ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }.environmentObject(catalog)
        }
    }

#endif

private struct AccountTabs: View {
    let account: AuthAccount
    var body: some View {
        TabView {
            NavigationStack {
                ContentUnavailableView(
                    "Your library is ready", systemImage: "film.stack",
                    description: Text(
                        "Your account is connected. Movie collection syncing is coming soon.")
                )
                .navigationTitle(account.libraryName).navigationBarTitleDisplayMode(.inline)
                .shogunCanvas()
            }.tabItem { Label("Library", systemImage: "square.grid.2x2") }
            AccountProfileView(account: account).tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
    }
}
