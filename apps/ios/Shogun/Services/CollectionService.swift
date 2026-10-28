import Foundation

struct CollectionSnapshot {
    let movies: [Movie]
    let libraries: [MovieLibrary]
    let memberships: [LibraryMembership]
    let copies: [OwnedCopy]
    let states: [PersonalMovieState]
    let defaultLibraryID: String?
}

enum CollectionFailure: Error, LocalizedError, Equatable {
    case unavailable, access, expired, invalid
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return
                "Cannot reach your collection. Check your connection and try again. Your input has been kept."
        case .access:
            return
                "Your access to this library may have changed. Refresh your collection and try again."
        case .expired: return "Your session has changed or expired. Sign in again to continue."
        case .invalid: return "Check the library, movie, and format, then try again."
        }
    }
}

@MainActor protocol CollectionServicing {
    func load() async throws -> CollectionSnapshot
    func saveCopy(id: String, libraryID: String, movieID: String, format: MovieFormat) async throws
    func saveState(_ state: PersonalMovieState) async throws
    func setDefault(libraryID: String) async throws
    func createLibrary(id: String, name: String) async throws
    func restorePersonalLibrary() async throws
}

/// Transport always obtains a fresh SDK session and checks the bound account before sending.
@MainActor final class SupabaseCollectionService: CollectionServicing {
    typealias RPC = @MainActor (String, Data) async throws -> Data
    private let rpc: RPC
    init(rpc: @escaping RPC) { self.rpc = rpc }

    func load() async throws -> CollectionSnapshot {
        let data = try await perform("collection_snapshot", Data("{}".utf8))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CollectionPayload.self, from: data).snapshot
    }
    func saveCopy(id: String, libraryID: String, movieID: String, format: MovieFormat) async throws
    {
        _ = try await call(
            "save_collection_copy",
            [
                "copy_id": id, "target_library": libraryID,
                "target_movie": movieID, "copy_format": format.rawValue,
            ])
    }
    func saveState(_ state: PersonalMovieState) async throws {
        _ = try await call(
            "save_movie_diary",
            [
                "target_movie": state.movieID,
                "is_watched": state.watched, "personal_rating": state.rating as Any? ?? NSNull(),
            ])
    }
    func setDefault(libraryID: String) async throws {
        _ = try await call("set_default_library", ["target_library": libraryID])
    }
    func createLibrary(id: String, name: String) async throws {
        _ = try await call("create_collection_library", ["request_id": id, "library_name": name])
    }
    func restorePersonalLibrary() async throws { _ = try await call("bootstrap_account", [:]) }
    private func call(_ name: String, _ body: [String: Any]) async throws -> Data {
        try await perform(name, JSONSerialization.data(withJSONObject: body))
    }
    private func perform(_ name: String, _ data: Data) async throws -> Data {
        do { return try await rpc(name, data) } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let failure = error as? CollectionFailure { throw failure }
            if (error as? SignInFailure) == .expired { throw CollectionFailure.expired }
            if let failure = error as? BackendHTTPError {
                if failure.status == 401 { throw CollectionFailure.expired }
                if failure.status == 403 { throw CollectionFailure.access }
            }
            throw CollectionFailure.unavailable
        }
    }
}

/// Backend wire types stay out of views and domain models. UUIDs are preserved verbatim.
private struct CollectionPayload: Decodable {
    struct Library: Decodable {
        let id: String
        let name: String
        let isShared: Bool
    }
    struct Membership: Decodable {
        let libraryId: String
        let userId: String
        let role: String
    }
    struct Film: Decodable {
        let id: String
        let title: String
        let releaseYear: Int?
        let synopsis: String
        let tmdbId: Int?
    }
    struct Copy: Decodable {
        let id: String
        let libraryId: String
        let movieId: String
        let format: MovieFormat
    }
    struct State: Decodable {
        let userId: String
        let movieId: String
        let watched: Bool
        let rating: Int?
    }
    let libraries: [Library]
    let memberships: [Membership]
    let movies: [Film]
    let copies: [Copy]
    let states: [State]
    let defaultLibraryId: String?
    var snapshot: CollectionSnapshot {
        CollectionSnapshot(
            movies: movies.map {
                Movie(
                    id: $0.id, title: $0.title, year: $0.releaseYear,
                    palette: $0.id.utf8.reduce(0) { ($0 + Int($1)) % 8 }, synopsis: $0.synopsis,
                    tmdbID: $0.tmdbId)
            },
            libraries: libraries.map {
                MovieLibrary(id: $0.id, name: $0.name, isShared: $0.isShared)
            },
            memberships: memberships.map {
                LibraryMembership(
                    userID: $0.userId, libraryID: $0.libraryId,
                    role: $0.role == "owner" ? .owner : ($0.role == "editor" ? .editor : .viewer))
            },
            copies: copies.map {
                OwnedCopy(
                    id: $0.id, libraryID: $0.libraryId, movieID: $0.movieId, format: $0.format)
            },
            states: states.map {
                PersonalMovieState(
                    userID: $0.userId, movieID: $0.movieId, watched: $0.watched, rating: $0.rating
                )
            },
            defaultLibraryID: defaultLibraryId)
    }
}
