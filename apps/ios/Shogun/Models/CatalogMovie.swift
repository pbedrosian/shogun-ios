import Foundation

/// Provider identity is intentionally separate from the UUID of a persisted collection movie.
struct CatalogMovie: Identifiable, Hashable {
    let id: Int
    let title: String
    let year: Int?
    let synopsis: String
    let posterURL: URL?
    let runtimeMinutes: Int?
    let genres: [String]
    let director: String?
    var releaseYearText: String { year.map(String.init) ?? "Unknown year" }
    // Rendering only: this namespaced ID is never persisted as a collection UUID.
    var placeholder: Movie {
        Movie(id: "tmdb:\(id)", title: title, year: year, palette: id % 8, synopsis: synopsis)
    }
}
struct CatalogPage {
    let page: Int
    let totalPages: Int
    let results: [CatalogMovie]
}
