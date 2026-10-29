import SwiftUI

struct AccountServices {
    let collection: any CollectionServicing
    let discovery: any MovieDiscoveryServicing
}

struct AuthRootView: View {
    let services: ((UUID) -> AccountServices)?
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
            if let service = services?(account.id) {
                ConnectedCollectionTabs(account: account, services: service).id(account.id)
            } else {
                VStack {
                    ContentUnavailableView(
                        "Collection connection unavailable", systemImage: "wifi.exclamationmark")
                    Button("Sign out", action: auth.signOut)
                }
            }
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
                FixtureSearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
                ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }.environmentObject(catalog)
        }
    }

#endif
