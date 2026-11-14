#if DEBUG
    import Foundation

    /// Explicit UI-test-only data, never selected by a normal Debug or Release launch.
    @MainActor final class CollectionUITestService: CollectionServicing {
        private let userID: String
        private var libraries: [MovieLibrary]
        private var copies: [OwnedCopy] = []
        private var states: [PersonalMovieState] = []
        private var defaultID: String?
        private var failLoad: Bool
        private var failSave: Bool
        private var addedMovies: [Movie] = []
        private var requests = Set<String>()
        private var coverPaths: [Int: String] = [:]
        static let sampleCovers = [
            "/pEzNVQfdzYDzVK0XqxERIw2x2se.jpg", "/x2FJsf1ElAgr63Y3PNPtJrcmpoe.jpg",
            "/3b4fRUYXFaGVDqkb0ikjB4cn7ub.jpg",
        ].map { path in
            MovieCover(
                path: path, url: URL(string: "https://image.tmdb.org/t/p/w342" + path)!,
                language: "en", width: 1000, height: 1500)
        }
        static var cover: MovieCover { sampleCovers[0] }
        func covers(tmdbID: Int) async throws -> [MovieCover] {
            if ProcessInfo.processInfo.arguments.contains("-cover-load-error") {
                throw CollectionFailure.unavailable
            }
            return ProcessInfo.processInfo.arguments.contains("-cover-empty")
                ? [] : Self.sampleCovers
        }
        func setCover(tmdbID: Int, path: String?) async throws {
            if failSave {
                failSave = false
                throw CollectionFailure.unavailable
            }
            coverPaths[tmdbID] = path
        }
        private let movie = Movie(
            id: "30000000-0000-0000-0000-000000000001", title: "Arrival", year: 2016, palette: 0,
            synopsis: "First contact", tmdbID: 329865)
        init(userID: UUID) {
            self.userID = userID.uuidString.lowercased()
            libraries =
                ProcessInfo.processInfo.arguments.contains("-collection-no-libraries")
                ? []
                : [
                    MovieLibrary(
                        id: "20000000-0000-0000-0000-000000000001", name: "My Library",
                        isShared: false)
                ]
            failLoad = ProcessInfo.processInfo.arguments.contains("-collection-load-error")
            failSave = ProcessInfo.processInfo.arguments.contains("-collection-save-error")
            if ProcessInfo.processInfo.arguments.contains("-cover-owned") {
                copies = [
                    OwnedCopy(
                        id: "cover-copy", libraryID: libraries[0].id,
                        movieID: movie.id, format: .uhd)
                ]
            }
        }
        func load() async throws -> CollectionSnapshot {
            if failLoad {
                failLoad = false
                throw CollectionFailure.unavailable
            }
            return CollectionSnapshot(
                movies: ([movie] + addedMovies).map { film in
                    Movie(
                        id: film.id, title: film.title, year: film.year, palette: film.palette,
                        synopsis: film.synopsis, tmdbID: film.tmdbID, director: film.director,
                        runtimeMinutes: film.runtimeMinutes, genres: film.genres,
                        posterURL: coverPaths[film.tmdbID ?? -1].flatMap {
                            URL(string: "https://image.tmdb.org/t/p/w342" + $0)
                        } ?? film.posterURL)
                }, libraries: libraries,
                memberships: libraries.map {
                    LibraryMembership(userID: userID, libraryID: $0.id, role: .owner)
                },
                copies: copies, states: states, defaultLibraryID: defaultID)
        }
        func editCopies(
            libraryID: String, movieID: String, expected: [OwnedCopy], formats: [MovieFormat]
        ) async throws {
            copies.removeAll { $0.libraryID == libraryID && $0.movieID == movieID }
            copies += formats.map {
                OwnedCopy(id: UUID().uuidString, libraryID: libraryID, movieID: movieID, format: $0)
            }
        }
        func addMovie(_ request: MovieAddRequest) async throws {
            if failSave {
                failSave = false
                throw CollectionFailure.unavailable
            }
            guard requests.insert(request.id).inserted else { return }
            let existing = ([movie] + addedMovies).first {
                request.providerID != nil && $0.tmdbID == request.providerID
            }
            let film =
                existing
                ?? Movie(
                    id: UUID().uuidString, title: request.metadata.title,
                    year: request.metadata.year, palette: 0, synopsis: request.metadata.synopsis,
                    tmdbID: request.providerID, director: request.metadata.director,
                    runtimeMinutes: request.metadata.runtimeMinutes,
                    genres: request.metadata.genres,
                    posterURL: MovieMetadata.artworkURL(request.metadata.posterURL))
            if existing == nil { addedMovies.append(film) }
            copies += request.formats.map {
                OwnedCopy(
                    id: UUID().uuidString,
                    libraryID: request.libraryID, movieID: film.id, format: $0)
            }
            if let choice = request.coverSelection, let providerID = request.providerID {
                coverPaths[providerID] = choice.path
            }
        }
        func saveState(_ state: PersonalMovieState) async throws {
            states.removeAll { $0.movieID == state.movieID }
            states.append(state)
        }
        func setDefault(libraryID: String) async throws { defaultID = libraryID }
        func createLibrary(id: String, name: String) async throws {
            if !libraries.contains(where: { $0.id == id }) {
                libraries.append(MovieLibrary(id: id, name: name, isShared: true))
            }
        }
        func restorePersonalLibrary() async throws {
            libraries = [
                MovieLibrary(
                    id: "20000000-0000-0000-0000-000000000001", name: "My Library", isShared: false)
            ]
        }
    }
#endif
