#if DEBUG
    import Foundation

    /// Selected only through the explicit authentication UI-test launch argument.
    @MainActor final class DiscoveryUITestService: MovieDiscoveryServicing {
        private var failSearch = ProcessInfo.processInfo.arguments.contains("-discovery-error")
        private var failDetails = ProcessInfo.processInfo.arguments.contains(
            "-discovery-detail-error")
        static let arrival = CatalogMovie(
            id: 329865, title: "Arrival", year: 2016, synopsis: "First contact.", posterURL: nil,
            runtimeMinutes: 116, genres: ["Science Fiction"], director: "Denis Villeneuve")
        func search(query: String, page: Int) async throws -> CatalogPage {
            if failSearch {
                failSearch = false
                throw DiscoveryFailure.unavailable
            }
            if query.lowercased() == "no matches" {
                return CatalogPage(page: page, totalPages: 0, results: [])
            }
            if query.lowercased() == "slow" { try await Task.sleep(for: .seconds(30)) }
            if page == 1 { return CatalogPage(page: 1, totalPages: 2, results: [Self.arrival]) }
            return CatalogPage(
                page: 2, totalPages: 2,
                results: [
                    CatalogMovie(
                        id: 11, title: "Star Wars", year: 1977, synopsis: "A galaxy far away.",
                        posterURL: nil, runtimeMinutes: 121, genres: [], director: nil)
                ])
        }
        func details(id: Int) async throws -> CatalogMovie {
            if failDetails {
                failDetails = false
                throw DiscoveryFailure.unavailable
            }
            return Self.arrival
        }
    }
#endif
