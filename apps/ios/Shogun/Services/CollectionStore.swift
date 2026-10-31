import Combine
import Foundation

/// Coordinates server-confirmed snapshots. CatalogStore remains synchronous domain/query logic.
@MainActor final class CollectionStore: ObservableObject {
    @Published private(set) var catalog: CatalogStore?
    @Published private(set) var isBusy = false
    @Published private(set) var error: String?
    @Published private(set) var defaultLibraryID: String?
    private let service: any CollectionServicing
    private let userID: String
    private let preferences: UserDefaults?
    private var active = true
    init(userID: UUID, service: any CollectionServicing, preferences: UserDefaults? = nil) {
        self.userID = userID.uuidString.lowercased()
        self.service = service
        self.preferences = preferences
    }
    func invalidate() {
        active = false
        catalog = nil
        error = nil
        defaultLibraryID = nil
    }
    func refresh() async {
        guard active, !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do { try await reload() } catch { report(error) }
    }
    private func reload() async throws {
        let snapshot = try await service.load()
        try Task.checkCancellation()
        guard active else { throw CancellationError() }
        // RLS is authoritative; filter memberships/states again to prevent mixed-account UI fixtures.
        let next = CatalogStore(
            movies: snapshot.movies, copies: snapshot.copies,
            libraries: snapshot.libraries, memberships: snapshot.memberships,
            userID: userID, personalStates: snapshot.states.filter { $0.userID == userID },
            preferences: preferences)
        let writable = Set(next.writableLibraries.map(\.id))
        defaultLibraryID = snapshot.defaultLibraryID.flatMap { writable.contains($0) ? $0 : nil }
        let previous = catalog?.selectedLibraryID
        next.selectedLibraryID =
            previous.flatMap { id in next.libraries.contains { $0.id == id } ? id : nil }
            ?? defaultLibraryID ?? next.libraries.first(where: { !$0.isShared })?.id ?? next
            .libraries.first?.id ?? ""
        if let old = catalog {
            next.libraryQuery = old.libraryQuery
            next.searchQuery = old.searchQuery
            next.libraryColumns = old.libraryColumns
        }
        if let catalog { catalog.replaceContents(from: next) } else { catalog = next }
    }
    func editCopies(
        libraryID: String, movieID: String, expected: [OwnedCopy], formats: [MovieFormat]
    ) async -> Bool {
        guard formats.count <= 99,
            catalog?.writableLibraries.contains(where: { $0.id == libraryID }) == true,
            expected.allSatisfy({ $0.libraryID == libraryID && $0.movieID == movieID })
        else {
            error = CollectionFailure.access.localizedDescription
            return false
        }
        return await write {
            try await self.service.editCopies(
                libraryID: libraryID, movieID: movieID, expected: expected, formats: formats)
        }
    }
    func addMovie(_ request: MovieAddRequest) async -> Bool {
        guard request.isValid else {
            error = CollectionFailure.invalid.localizedDescription
            return false
        }
        guard catalog?.writableLibraries.contains(where: { $0.id == request.libraryID }) == true
        else {
            error = CollectionFailure.access.localizedDescription
            return false
        }
        return await write { try await self.service.addMovie(request) }
    }
    func saveDiary(_ state: PersonalMovieState) async -> Bool {
        guard state.userID == userID,
            catalog?.movies.contains(where: { $0.id == state.movieID }) == true,
            state.rating.map({ (1...5).contains($0) }) ?? true
        else {
            error = CollectionFailure.invalid.localizedDescription
            return false
        }
        return await write { try await self.service.saveState(state) }
    }
    func setDefault(libraryID: String) async -> Bool {
        guard catalog?.writableLibraries.contains(where: { $0.id == libraryID }) == true else {
            error = CollectionFailure.access.localizedDescription
            return false
        }
        return await write { try await self.service.setDefault(libraryID: libraryID) }
    }
    func createLibrary(id: String, name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else {
            error = CollectionFailure.invalid.localizedDescription
            return false
        }
        return await write { try await self.service.createLibrary(id: id, name: name) }
    }
    func restorePersonalLibrary() async -> Bool {
        await write { try await self.service.restorePersonalLibrary() }
    }
    private func write(_ action: () async throws -> Void) async -> Bool {
        guard active, !isBusy else { return false }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await action()
            try Task.checkCancellation()
            try await reload()
            return true
        } catch {
            report(error)
            return false
        }
    }
    private func report(_ failure: Error) {
        guard active, !(failure is CancellationError), !Task.isCancelled else { return }
        error = (failure as? CollectionFailure ?? .unavailable).localizedDescription
    }
}
