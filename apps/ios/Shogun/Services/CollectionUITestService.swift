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
        }
        func load() async throws -> CollectionSnapshot {
            if failLoad {
                failLoad = false
                throw CollectionFailure.unavailable
            }
            return CollectionSnapshot(
                movies: [movie], libraries: libraries,
                memberships: libraries.map {
                    LibraryMembership(userID: userID, libraryID: $0.id, role: .owner)
                },
                copies: copies, states: states, defaultLibraryID: defaultID)
        }
        func saveCopy(id: String, libraryID: String, movieID: String, format: MovieFormat)
            async throws
        {
            if failSave {
                failSave = false
                throw CollectionFailure.unavailable
            }
            if !copies.contains(where: { $0.id == id }) {
                copies.append(
                    OwnedCopy(id: id, libraryID: libraryID, movieID: movieID, format: format))
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
