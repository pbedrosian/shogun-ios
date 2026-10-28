import Foundation

enum MovieFormat: String, CaseIterable, Identifiable, Codable {
    case vhs = "VHS"
    case dvd = "DVD"
    case bluRay = "Blu-ray"
    case uhd = "4K UHD"
    case digital = "Digital"
    var id: String { rawValue }
}
struct Movie: Identifiable, Hashable {
    let id: String  // Stable backend metadata UUID; Debug fixtures also use readable string IDs.
    let title: String
    let year: Int?
    let palette: Int
    var releaseYearText: String { year.map(String.init) ?? "Unknown year" }
    let synopsis: String
    let tmdbID: Int?
    init(id: String, title: String, year: Int?, palette: Int, synopsis: String, tmdbID: Int? = nil)
    {
        self.id = id
        self.title = title
        self.year = year
        self.palette = palette
        self.synopsis = synopsis
        self.tmdbID = tmdbID
    }
}
struct MovieLibrary: Identifiable {
    let id: String
    let name: String
    let isShared: Bool
}
enum LibraryRole { case owner, editor, viewer }
struct LibraryMembership {
    let userID: String
    let libraryID: String
    let role: LibraryRole
}
struct OwnedCopy: Identifiable {
    let id: String
    let libraryID: String
    let movieID: String
    let format: MovieFormat
}
struct PersonalMovieState {
    let userID: String
    let movieID: String
    var watched = false
    var rating: Int? = nil
}
