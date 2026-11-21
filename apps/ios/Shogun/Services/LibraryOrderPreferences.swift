import Foundation

/// Device-local, account-scoped storage; it does not decide how movies are ordered.
struct LibraryOrderPreferences {
    private let defaults: UserDefaults?
    private let key: String

    init(userID: String, defaults: UserDefaults?) {
        self.defaults = defaults
        key = "library.customOrder.v1.\(userID)"
    }
    func load() -> [String: [String]] {
        defaults?.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }
    func save(_ orders: [String: [String]]) { defaults?.set(orders, forKey: key) }
}
