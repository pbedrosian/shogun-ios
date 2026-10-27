import Foundation

enum DiscoveryFailure: Error, LocalizedError, Equatable {
    case unavailable, notConfigured, rateLimited, expired, notFound
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Movie search is unavailable. Check your connection and try again."
        case .notConfigured: return "Movie search is not configured yet. Please try again later."
        case .rateLimited: return "Movie search is busy. Wait a moment, then try again."
        case .expired: return "Your session has expired. Sign in again to search movies."
        case .notFound: return "This movie is no longer available in the catalog."
        }
    }
}
@MainActor protocol MovieDiscoveryServicing {
    func search(query: String, page: Int) async throws -> CatalogPage
    func details(id: Int) async throws -> CatalogMovie
}

@MainActor struct MovieDiscoveryService: MovieDiscoveryServicing {
    typealias Request = @MainActor (Data) async throws -> Data
    private let request: Request
    init(request: @escaping Request) { self.request = request }
    func search(query: String, page: Int) async throws -> CatalogPage {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CatalogPage(page: 1, totalPages: 0, results: []) }
        guard query.count <= 200, (1...500).contains(page) else {
            throw DiscoveryFailure.unavailable
        }
        let data = try await send(["operation": "search", "query": query, "page": page])
        let value = try JSONDecoder().decode(PagePayload.self, from: data)
        guard value.page == page, (0...500).contains(value.totalPages) else {
            throw DiscoveryFailure.unavailable
        }
        return CatalogPage(
            page: value.page, totalPages: value.totalPages, results: value.results.map(\.movie))
    }
    func details(id: Int) async throws -> CatalogMovie {
        guard id > 0 else { throw DiscoveryFailure.notFound }
        let data = try await send(["operation": "details", "movieID": id])
        let value = try JSONDecoder().decode(FilmPayload.self, from: data)
        guard value.id == id else { throw DiscoveryFailure.unavailable }
        return value.movie
    }
    private func send(_ body: [String: Any]) async throws -> Data {
        do { return try await request(JSONSerialization.data(withJSONObject: body)) } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let error = error as? DiscoveryFailure { throw error }
            if (error as? SignInFailure) == .expired { throw DiscoveryFailure.expired }
            if let error = error as? BackendHTTPError {
                if error.status == 401 { throw DiscoveryFailure.expired }
                if error.status == 429 { throw DiscoveryFailure.rateLimited }
                if error.status == 404 { throw DiscoveryFailure.notFound }
                if error.code == "catalog_not_configured" { throw DiscoveryFailure.notConfigured }
            }
            throw DiscoveryFailure.unavailable
        }
    }
}
private struct PagePayload: Decodable {
    let page: Int
    let totalPages: Int
    let results: [FilmPayload]
}
private struct FilmPayload: Decodable {
    let id: Int
    let title: String
    let year: Int?
    let synopsis: String
    let posterURL: URL?
    let runtimeMinutes: Int?
    let genres: [String]
    let director: String?
    var movie: CatalogMovie {
        let artwork = posterURL.flatMap { url in
            url.scheme == "https" && url.host == "image.tmdb.org" && url.user == nil
                && url.password == nil && url.port == nil && url.path.hasPrefix("/t/p/") ? url : nil
        }
        return CatalogMovie(
            id: id, title: title, year: year, synopsis: synopsis, posterURL: artwork,
            runtimeMinutes: runtimeMinutes, genres: genres, director: director)
    }
}
