import SwiftUI

struct AccountProfileView: View {
    let account: AuthAccount
    @EnvironmentObject private var auth: AuthStore
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProfileHeader(name: "Shogun account", email: account.email, badge: "Signed in")
                }
                Section("Your personal library") {
                    Label(account.libraryName, systemImage: "person").badge("Personal")
                }
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
                .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
    }
}
