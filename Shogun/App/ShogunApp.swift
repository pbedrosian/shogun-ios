import SwiftUI

@main struct ShogunApp: App {
    @StateObject private var store = CatalogStore()
    init() {
        ShogunSystemAppearance.configure()
    }
    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView().tabItem { Label("Library", systemImage: "square.grid.2x2") }
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
                ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }.tint(ShogunTheme.accent).environmentObject(store)
        }
    }
}
