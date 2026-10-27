import Foundation

enum MovieFormat: String, CaseIterable, Identifiable, Codable {
    case vhs = "VHS", dvd = "DVD", bluRay = "Blu-ray", uhd = "4K UHD", digital = "Digital"
    var id: String { rawValue }
}
struct Movie: Identifiable, Hashable {
    let id: String // Stable local metadata identifier; future providers map to this record.
    let title: String
    let year: Int
    let palette: Int
    let synopsis: String
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
