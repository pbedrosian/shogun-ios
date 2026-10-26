import SwiftUI

@main struct ShogunApp: App {
    @StateObject private var auth: AuthStore
    init() {
        ShogunSystemAppearance.configure()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-shogun-demo") {
            _auth = StateObject(wrappedValue: AuthStore(service: nil, demo: true)); return
        }
        if ProcessInfo.processInfo.arguments.contains("-shogun-auth-ui") {
            _auth = StateObject(wrappedValue: AuthStore(service: AuthUITestService())); return
        }
        let allowHTTP = true
        #else
        let allowHTTP = false
        #endif
        let config = try? AuthConfiguration(info: Bundle.main.infoDictionary ?? [:], allowLocalHTTP: allowHTTP)
        _auth = StateObject(wrappedValue: AuthStore(service: config.map { SupabaseAuthService(config: $0) }))
    }
    var body: some Scene {
        WindowGroup { AuthRootView().environmentObject(auth) }
    }
}
