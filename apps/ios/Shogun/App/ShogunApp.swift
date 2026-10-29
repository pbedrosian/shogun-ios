import SwiftUI

@main struct ShogunApp: App {
    private let services: ((UUID) -> AccountServices)?
    @StateObject private var auth: AuthStore
    init() {
        ShogunSystemAppearance.configure()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-shogun-demo") {
                services = nil
                _auth = StateObject(wrappedValue: AuthStore(service: nil, demo: true))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-shogun-auth-ui") {
                services = {
                    AccountServices(
                        collection: CollectionUITestService(userID: $0),
                        discovery: DiscoveryUITestService())
                }
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
        services = service.map { auth in
            { userID in
                let backend = auth.backendClient(for: userID)
                return AccountServices(
                    collection: SupabaseCollectionService(catalog: {
                        try await backend.function("catalog", body: $0)
                    }) { try await backend.rpc($0, body: $1) },
                    discovery: MovieDiscoveryService {
                        try await backend.function("catalog", body: $0)
                    })
            }
        }
    }
    private var fixtureAppearance: ColorScheme? {
        #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-shogun-auth-ui") || args.contains("-shogun-demo"),
                let index = args.firstIndex(of: "-AppleInterfaceStyle"), index + 1 < args.count
            {
                return args[index + 1] == "Dark" ? .dark : .light
            }
        #endif
        return nil
    }
    var body: some Scene {
        WindowGroup {
            AuthRootView(services: services).environmentObject(auth).preferredColorScheme(
                fixtureAppearance)
        }
    }
}
