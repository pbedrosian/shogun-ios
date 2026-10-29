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
    case unavailable, access, expired, invalid, conflict
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return
                "Cannot reach your collection. Check your connection and try again. Your input has been kept."
        case .access:
            return
                "Your access to this library may have changed. Refresh your collection and try again."
        case .expired: return "Your session has changed or expired. Sign in again to continue."
        case .conflict:
            return
                "Copies changed on another device. Refresh your collection, then close and reopen this editor to review them."
        case .invalid: return "Check the library, movie, and format, then try again."
        }
    }
}

@MainActor protocol CollectionServicing {
    func addMovie(_ request: MovieAddRequest) async throws
    func editCopies(
        libraryID: String, movieID: String, expected: [OwnedCopy], formats: [MovieFormat])
        async throws
    func load() async throws -> CollectionSnapshot
    func saveState(_ state: PersonalMovieState) async throws
    func setDefault(libraryID: String) async throws
    func createLibrary(id: String, name: String) async throws
    func restorePersonalLibrary() async throws
}

/// Transport always obtains a fresh SDK session and checks the bound account before sending.
@MainActor final class SupabaseCollectionService: CollectionServicing {
    typealias RPC = @MainActor (String, Data) async throws -> Data
    private let rpc: RPC
    private let catalog: MovieDiscoveryService.Request?
    init(catalog: MovieDiscoveryService.Request? = nil, rpc: @escaping RPC) {
        self.rpc = rpc
        self.catalog = catalog
    }
    func editCopies(
        libraryID: String, movieID: String, expected: [OwnedCopy], formats: [MovieFormat]
    ) async throws {
        _ = try await call(
            "edit_collection_copies",
            [
                "target_library": libraryID, "target_movie": movieID,
                "expected_copies": expected.sorted { $0.id < $1.id }.map {
                    ["id": $0.id, "format": $0.format.rawValue]
                },
                "copy_formats": formats.map(\.rawValue),
            ])
    }
    func addMovie(_ request: MovieAddRequest) async throws {
        guard request.isValid else { throw CollectionFailure.invalid }
        if let providerID = request.providerID {
            guard let catalog else { throw CollectionFailure.unavailable }
            do {
                _ = try await catalog(
                    JSONSerialization.data(withJSONObject: [
                        "operation": "import", "movieID": providerID, "requestID": request.id,
                        "libraryID": request.libraryID, "formats": request.formats.map(\.rawValue),
                    ]))
            } catch { throw map(error) }
        } else {
            let metadata = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(request.metadata))
            _ = try await call(
                "add_manual_movie",
                [
                    "request_id": request.id,
                    "target_library": request.libraryID, "metadata": metadata,
                    "copy_formats": request.formats.map(\.rawValue),
                ])
        }
    }

    func load() async throws -> CollectionSnapshot {
        let data = try await perform("collection_snapshot", Data("{}".utf8))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CollectionPayload.self, from: data).snapshot
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
        do { return try await rpc(name, data) } catch { throw map(error) }
    }
    private func map(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return CancellationError()
        }
        if let failure = error as? CollectionFailure { return failure }
        if (error as? SignInFailure) == .expired { return CollectionFailure.expired }
        if let failure = error as? BackendHTTPError {
            if failure.status == 401 { return CollectionFailure.expired }
            if failure.status == 403 { return CollectionFailure.access }
            if failure.status == 409 { return CollectionFailure.conflict }
            if failure.status == 400 { return CollectionFailure.invalid }
        }
        return CollectionFailure.unavailable
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
        let director: String?
        let runtimeMinutes: Int?
        let genres: [String]?
        let posterPath: String?
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
                    tmdbID: $0.tmdbId, director: $0.director, runtimeMinutes: $0.runtimeMinutes,
                    genres: $0.genres ?? [],
                    posterURL: $0.posterPath.flatMap(MovieMetadata.artworkURL))
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
