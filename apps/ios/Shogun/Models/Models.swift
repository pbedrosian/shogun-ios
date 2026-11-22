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
    let director: String?
    let runtimeMinutes: Int?
    let genres: [String]
    let posterURL: URL?
    let tmdbID: Int?
    init(
        id: String, title: String, year: Int?, palette: Int, synopsis: String, tmdbID: Int? = nil,
        director: String? = nil, runtimeMinutes: Int? = nil, genres: [String] = [],
        posterURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.palette = palette
        self.synopsis = synopsis
        self.tmdbID = tmdbID
        self.director = director
        self.runtimeMinutes = runtimeMinutes
        self.genres = genres
        self.posterURL = posterURL
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
enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case titleAscending = "Title A–Z"
    case titleDescending = "Title Z–A"
    case custom = "Custom"
    var id: String { rawValue }
}

struct OwnedCopy: Identifiable {
    let id: String
    let libraryID: String
    let movieID: String
    let format: MovieFormat
    var createdAt: Date? = nil
}
struct PersonalMovieState {
    let userID: String
    let movieID: String
    var watched = false
    var rating: Int? = nil
}

/// Pure ordering rules, independent of views, storage and copy ownership.
enum LibraryCustomOrder {
    static func reconcile(_ saved: [String], available: [String]) -> [String] {
        let allowed = Set(available)
        var seen = Set<String>()
        var order = saved.filter { allowed.contains($0) && seen.insert($0).inserted }
        order.append(contentsOf: available.filter { seen.insert($0).inserted })
        return order
    }
    static func move(_ movieID: String, to targetID: String, in saved: [String]) -> [String]? {
        guard movieID != targetID, let source = saved.firstIndex(of: movieID),
            let target = saved.firstIndex(of: targetID)
        else { return nil }
        var order = saved
        order.remove(at: source)
        order.insert(movieID, at: min(target, order.count))
        return order
    }
}
