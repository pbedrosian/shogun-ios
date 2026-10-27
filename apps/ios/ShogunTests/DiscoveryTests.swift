import XCTest

@testable import Shogun

@MainActor final class DiscoveryTests: XCTestCase {
    static let first = CatalogMovie(
        id: 329865, title: "Arrival", year: 2016, synopsis: "First contact", posterURL: nil,
        runtimeMinutes: 116, genres: ["Science Fiction"], director: "Denis Villeneuve")
    static let second = CatalogMovie(
        id: 11, title: "Star Wars", year: nil, synopsis: "", posterURL: nil, runtimeMinutes: nil,
        genres: [], director: nil)
    @MainActor final class Fake: MovieDiscoveryServicing {
        var calls: [(String, Int)] = []
        var fail = false
        var pending: ((String, Int) async throws -> CatalogPage)?
        var detailPending: (() async throws -> CatalogMovie)?
        func search(query: String, page: Int) async throws -> CatalogPage {
            calls.append((query, page))
            if let pending { return try await pending(query, page) }
            if fail { throw DiscoveryFailure.rateLimited }
            return CatalogPage(
                page: page, totalPages: 2,
                results: page == 1
                    ? [DiscoveryTests.first] : [DiscoveryTests.first, DiscoveryTests.second])
        }
        func details(id: Int) async throws -> CatalogMovie {
            if let detailPending { return try await detailPending() }
            if fail { throw DiscoveryFailure.notFound }
            return DiscoveryTests.first
        }
    }
    func settle(_ store: CatalogSearchStore) async {
        for _ in 0..<1000 {
            if store.phase != .loading && store.phase != .loadingMore { return }
            await Task.yield()
        }
        XCTFail("Search did not settle")
    }
    func testBlankQueriesDebounceAndPaginationRetryDeduplicate() async {
        let fake = Fake()
        let store = CatalogSearchStore(service: Fake(), debounce: .seconds(30))
        store.query = "pending"
        store.search()
        store.query = "  \n "
        store.search()
        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(store.results.isEmpty)
        store.invalidate()
        let search = CatalogSearchStore(service: fake, debounce: .zero)
        search.query = " Arrival "
        search.search()
        await settle(search)
        XCTAssertEqual(fake.calls.first?.0, "Arrival")
        XCTAssertEqual(search.results.map(\.id), [329865])
        XCTAssertTrue(search.canLoadMore)
        fake.fail = true
        search.loadMore()
        await settle(search)
        XCTAssertNotNil(search.error)
        XCTAssertEqual(search.page, 1)
        XCTAssertEqual(search.results.count, 1)
        fake.fail = false
        search.retry()
        await settle(search)
        XCTAssertEqual(search.results.map(\.id), [329865, 11])
        XCTAssertFalse(search.canLoadMore)
        search.loadMore()
        XCTAssertEqual(fake.calls.count, 3)
        search.query = " "
        search.search()
        XCTAssertTrue(search.results.isEmpty)
        XCTAssertNil(search.error)
    }
    func testFailureEmptyResultsAndImmediateRetry() async {
        let fake = Fake()
        fake.fail = true
        let store = CatalogSearchStore(service: fake, debounce: .zero)
        store.query = "Arrival"
        store.search(immediately: true)
        await settle(store)
        XCTAssertEqual(store.phase, .failed)
        XCTAssertNotNil(store.error)
        fake.fail = false
        fake.pending = { _, page in CatalogPage(page: page, totalPages: 0, results: []) }
        store.retry()
        await settle(store)
        XCTAssertEqual(store.phase, .empty)
        XCTAssertNil(store.error)
    }
    func testObsoleteResponseCannotReturnAfterNewQueryOrSignOut() async {
        let fake = Fake()
        var release: CheckedContinuation<CatalogPage, Never>?
        fake.pending = { query, page in
            if query == "old" { return await withCheckedContinuation { release = $0 } }
            return CatalogPage(page: page, totalPages: 1, results: [Self.second])
        }
        let store = CatalogSearchStore(service: fake, debounce: .zero)
        store.query = "old"
        store.search()
        while release == nil { await Task.yield() }
        store.query = "new"
        store.search()
        await settle(store)
        release?.resume(returning: CatalogPage(page: 1, totalPages: 1, results: [Self.first]))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(store.results.map(\.id), [11])
        release = nil
        store.query = "old"
        store.search()
        while release == nil { await Task.yield() }
        store.invalidate()
        release?.resume(returning: CatalogPage(page: 1, totalPages: 1, results: [Self.first]))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.query, "")
        store.search()
        store.loadMore()
        XCTAssertEqual(store.phase, .idle)
    }
    func testDetailFailureRetryAndCancelledResponse() async {
        let fake = Fake()
        fake.fail = true
        let detail = CatalogDetailStore(movie: Self.second, service: fake)
        await detail.load()
        XCTAssertNotNil(detail.error)
        XCTAssertEqual(detail.movie.id, 11)
        fake.fail = false
        await detail.load()
        XCTAssertNil(detail.error)
        XCTAssertEqual(detail.movie.id, 329865)
        var release: CheckedContinuation<CatalogMovie, Never>?
        fake.detailPending = { await withCheckedContinuation { release = $0 } }
        let task = Task { await detail.load() }
        while release == nil { await Task.yield() }
        await detail.load()
        XCTAssertTrue(detail.isLoading)
        task.cancel()
        release?.resume(returning: Self.second)
        await task.value
        XCTAssertEqual(detail.movie.id, 329865)
        XCTAssertFalse(detail.isLoading)
        XCTAssertNil(detail.error)
    }
    func testProviderOwnershipNeverMatchesManualTitle() {
        let manual = Movie(id: "manual", title: "Arrival", year: 2016, palette: 0, synopsis: "")
        let tmdb = Movie(
            id: "provider-record", title: "Arrival", year: 2016, palette: 0, synopsis: "",
            tmdbID: 329865)
        let store = CatalogStore(
            movies: [manual, tmdb],
            copies: [OwnedCopy(id: "copy", libraryID: "personal", movieID: tmdb.id, format: .dvd)],
            libraries: Fixtures.libraries, memberships: Fixtures.memberships, userID: "me",
            personalStates: [])
        XCTAssertEqual(store.ownedMovie(tmdbID: 329865)?.id, "provider-record")
        XCTAssertNil(store.ownedMovie(tmdbID: 11))
        XCTAssertEqual(Self.first.placeholder.id, "tmdb:329865")
        XCTAssertEqual(Self.first.releaseYearText, "2016")
        XCTAssertEqual(Self.second.releaseYearText, "Unknown year")
    }
}
