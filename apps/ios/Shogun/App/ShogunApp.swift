import SwiftUI

@main struct ShogunApp: App {
    private let collectionFactory: ((UUID) -> any CollectionServicing)?
    @StateObject private var auth: AuthStore
    init() {
        ShogunSystemAppearance.configure()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-shogun-demo") {
                collectionFactory = nil
                _auth = StateObject(wrappedValue: AuthStore(service: nil, demo: true))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-shogun-auth-ui") {
                collectionFactory = { CollectionUITestService(userID: $0) }
                _auth = StateObject(wrappedValue: AuthStore(service: AuthUITestService()))
                return
            }
            let allowHTTP = true
        #else
            let allowHTTP = false
        #endif
        let config = try? AuthConfiguration(
            info: Bundle.main.infoDictionary ?? [:], allowLocalHTTP: allowHTTP)
        let service = config.map { SupabaseAuthService(config: $0) }
        _auth = StateObject(wrappedValue: AuthStore(service: service))
        collectionFactory = { userID in
            SupabaseCollectionService { name, body in
                guard let service else { throw CollectionFailure.expired }
                return try await service.collectionRPC(name, body: body, userID: userID)
            }
        }
    }
    var body: some Scene {
        WindowGroup { AuthRootView(collectionFactory: collectionFactory).environmentObject(auth) }
    }
}
