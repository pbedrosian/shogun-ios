import XCTest

@testable import Shogun

final class SearchTests: XCTestCase {
    func testEmptyGlobalQueryReturnsWholeCatalogIncludingUnowned() throws {
        XCTAssertEqual(Fixtures.store().searchResults, Fixtures.movies)
    }

    func testGlobalSearchMatchesTitleIgnoringCase() throws {
        let store = Fixtures.store()
        store.searchQuery = "RRIv"
        XCTAssertEqual(store.searchResults.map(\.id), ["arrival"])
    }

    func testGlobalSearchMatchesReleaseYear() throws {
        let store = Fixtures.store()
        store.searchQuery = "2016"
        XCTAssertEqual(store.searchResults.map(\.id), ["arrival", "unowned"])
    }

    func testGlobalSearchMatchesPartialYear() throws {
        let store = Fixtures.store()
        store.searchQuery = "197"
        XCTAssertEqual(store.searchResults.map(\.id), ["jaws"])
    }

    func testNoMatchReturnsEmptyResults() throws {
        let store = Fixtures.store()
        store.searchQuery = "no such movie"
        XCTAssertTrue(store.searchResults.isEmpty)
    }

    func testGlobalSearchIsIndependentOfSelectedLibrary() throws {
        let store = Fixtures.store()
        store.selectedLibraryID = "family"
        store.searchQuery = "unowned"
        XCTAssertEqual(store.searchResults.map(\.id), ["unowned"])
    }

    func testLibrarySearchIsScopedAndDeduplicated() throws {
        let store = Fixtures.store()
        store.libraryQuery = "ARR"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        store.selectedLibraryID = "readonly"
        XCTAssertTrue(store.libraryResults.isEmpty)
    }

    func testLibrarySearchDoesNotMatchYear() throws {
        let store = Fixtures.store()
        store.libraryQuery = "2016"
        XCTAssertTrue(store.libraryResults.isEmpty)
    }

    func testEmptyLibraryQueryReturnsSelectedLibraryMovies() throws {
        let store = Fixtures.store()
        store.selectedLibraryID = "readonly"
        XCTAssertEqual(store.libraryResults.map(\.id), ["jaws"])
    }

    func testClearingQueriesRestoresResults() throws {
        let store = Fixtures.store()
        store.searchQuery = "absent"
        store.libraryQuery = "absent"
        store.searchQuery = ""
        store.libraryQuery = ""
        XCTAssertEqual(store.searchResults, Fixtures.movies)
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
    }

    func testQueriesAreIndependent() throws {
        let store = Fixtures.store()
        store.searchQuery = "jaws"
        store.libraryQuery = "arrival"
        XCTAssertEqual(store.searchResults.map(\.id), ["jaws"])
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
    }

    func testWhitespaceIsLiteralRatherThanSilentlyTrimmed() throws {
        let store = Fixtures.store()
        store.searchQuery = " Arrival "
        XCTAssertTrue(store.searchResults.isEmpty)
    }

    func testLibraryResultsRefreshAfterCopyAdded() throws {
        let store = Fixtures.store()
        store.libraryQuery = "unowned"
        XCTAssertTrue(store.libraryResults.isEmpty)
        XCTAssertTrue(store.addCopy(movie: Fixtures.unowned, format: .dvd, libraryID: "personal"))
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned"])
    }

    func testLibraryFormatsCombineAsUnionWithSearchAndLibraryScope() {
        let store = Fixtures.store()
        store.libraryFormats = [.dvd]
        XCTAssertTrue(store.libraryResults.isEmpty)  // Family DVD must not match personal UHD.
        store.selectedLibraryID = "family"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        store.libraryFormats = [.dvd, .vhs]
        store.libraryQuery = "ARR"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        store.selectedLibraryID = "readonly"
        XCTAssertTrue(store.libraryResults.isEmpty)
        store.libraryQuery = ""
        XCTAssertEqual(store.libraryResults.map(\.id), ["jaws"])
        store.libraryFormats.removeAll()
        store.selectedLibraryID = "personal"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        XCTAssertEqual(store.copies.count, Fixtures.copies.count)
    }

    func testRecentlyAddedUsesNewestCopyInSelectedLibraryAndKeepsSingleCard() {
        let copies = [
            OwnedCopy(
                id: "1", libraryID: "personal", movieID: "arrival", format: .dvd,
                createdAt: Date(timeIntervalSince1970: 10)),
            OwnedCopy(
                id: "2", libraryID: "personal", movieID: "arrival", format: .vhs,
                createdAt: Date(timeIntervalSince1970: 30)),
            OwnedCopy(
                id: "3", libraryID: "personal", movieID: "jaws", format: .dvd,
                createdAt: Date(timeIntervalSince1970: 20)),
            OwnedCopy(
                id: "4", libraryID: "family", movieID: "jaws", format: .dvd,
                createdAt: Date(timeIntervalSince1970: 40)),
            OwnedCopy(id: "5", libraryID: "personal", movieID: "unowned", format: .dvd),
        ]
        let store = CatalogStore(
            movies: Fixtures.movies.reversed(), copies: copies,
            libraries: Fixtures.libraries, memberships: Fixtures.memberships,
            userID: "me", personalStates: [])
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
        store.libraryFormats = [.dvd]
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
        store.librarySort = .titleDescending
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned", "jaws", "arrival"])
        store.librarySort = .titleAscending
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
    }

    func testLibrarySortTiesUseYearThenStableIDAndMissingDatesSortLast() {
        let movies = [
            Movie(id: "b", title: "Same", year: 2000, palette: 0, synopsis: ""),
            Movie(id: "a", title: "Same", year: 2000, palette: 0, synopsis: ""),
            Movie(id: "old", title: "Same", year: 1990, palette: 0, synopsis: ""),
            Movie(id: "missing", title: "A", year: nil, palette: 0, synopsis: ""),
        ]
        let copies = movies.map {
            OwnedCopy(
                id: $0.id, libraryID: "personal", movieID: $0.id, format: .dvd,
                createdAt: $0.id == "missing" ? nil : Date(timeIntervalSince1970: 10))
        }
        let store = CatalogStore(
            movies: movies, copies: copies, libraries: Fixtures.libraries,
            memberships: Fixtures.memberships, userID: "me", personalStates: [])
        XCTAssertEqual(store.libraryResults.map(\.id), ["old", "a", "b", "missing"])
        store.librarySort = .titleAscending
        XCTAssertEqual(store.libraryResults.map(\.id), ["missing", "old", "a", "b"])
        store.librarySort = .titleDescending
        XCTAssertEqual(store.libraryResults.map(\.id), ["old", "a", "b", "missing"])
    }

    func testTenThousandMovieLibraryCombinesSortFiltersAndSearch() {
        let movies = (0..<10_000).map {
            Movie(
                id: "movie-\($0)", title: String(format: "Movie %05d", $0), year: 2000,
                palette: 0, synopsis: "")
        }
        var copies = movies.enumerated().map { index, movie in
            OwnedCopy(
                id: movie.id, libraryID: "personal", movieID: movie.id, format: .dvd,
                createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        copies += movies.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { index, movie in
            OwnedCopy(id: "vhs-\(index)", libraryID: "personal", movieID: movie.id, format: .vhs)
        }
        let store = CatalogStore(
            movies: movies, copies: copies, libraries: Fixtures.libraries,
            memberships: Fixtures.memberships, userID: "me", personalStates: [])
        let start = Date()
        let all = store.libraryResults
        XCTAssertEqual(all.count, 10_000)
        XCTAssertEqual(all.first?.id, "movie-9999")
        store.libraryFormats = [.vhs]
        store.librarySort = .titleAscending
        let filtered = store.libraryResults
        XCTAssertEqual(filtered.count, 5_000)
        XCTAssertEqual(filtered.first?.id, "movie-0")
        store.libraryQuery = "09998"
        XCTAssertEqual(store.libraryResults.map(\.id), ["movie-9998"])
        store.selectedLibraryID = "hidden"
        XCTAssertTrue(store.libraryResults.isEmpty)
        print(
            "10,000-movie sort/filter/search sequence: \(Date().timeIntervalSince(start)) seconds")
    }

    func testMatchingTitlesPlaceUnknownYearsAfterKnownYearsInEitherInputOrder() {
        let known = Movie(id: "known", title: "Same", year: 2000, palette: 0, synopsis: "")
        let unknown = Movie(id: "unknown", title: "Same", year: nil, palette: 0, synopsis: "")
        for movies in [[known, unknown], [unknown, known]] {
            let copies = movies.map {
                OwnedCopy(id: $0.id, libraryID: "personal", movieID: $0.id, format: .dvd)
            }
            let store = CatalogStore(
                movies: movies, copies: copies, libraries: Fixtures.libraries,
                memberships: Fixtures.memberships, userID: "me", personalStates: [])
            for sort in LibrarySort.allCases {
                store.librarySort = sort
                XCTAssertEqual(store.libraryResults.map(\.id), ["known", "unknown"])
            }
        }
    }

    private func arrangedStore(preferences: UserDefaults? = nil, user: String = "me")
        -> CatalogStore
    {
        CatalogStore(
            movies: Fixtures.movies,
            copies: ["personal", "family"].flatMap { library in
                Fixtures.movies.map {
                    OwnedCopy(id: library + $0.id, libraryID: library, movieID: $0.id, format: .dvd)
                }
            },
            libraries: Fixtures.libraries,
            memberships: ["personal", "family"].map {
                LibraryMembership(userID: user, libraryID: $0, role: .viewer)
            }, userID: user, personalStates: [], preferences: preferences)
    }

    func testCustomArrangementSurvivesOtherSortsAndKeepsCopiesUnchanged() {
        let store = arrangedStore()
        let copyIDs = store.copies.map(\.id)
        store.librarySort = .titleDescending
        store.selectLibrarySort(.custom)
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned", "jaws", "arrival"])
        store.moveCustomMovie("arrival", to: "unowned")
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "unowned", "jaws"])
        store.selectLibrarySort(.titleAscending)
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
        store.selectLibrarySort(.custom)
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "unowned", "jaws"])
        XCTAssertEqual(store.copies.map(\.id), copyIDs)
    }

    func testCustomArrangementPersistsPerUserAndLibrary() {
        let suite = "custom-order-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = arrangedStore(preferences: preferences)
        store.moveCustomMovie("unowned", to: "arrival")
        store.selectedLibraryID = "family"
        store.moveCustomMovie("jaws", to: "arrival")
        let restored = arrangedStore(preferences: preferences)
        restored.selectLibrarySort(.custom)
        XCTAssertEqual(restored.libraryResults.map(\.id), ["unowned", "arrival", "jaws"])
        restored.selectedLibraryID = "family"
        XCTAssertEqual(restored.libraryResults.map(\.id), ["jaws", "arrival", "unowned"])
        let other = arrangedStore(preferences: preferences, user: "other")
        other.selectedLibraryID = "family"
        other.selectLibrarySort(.custom)
        XCTAssertEqual(other.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
    }

    func testFilteredReorderingPreservesHiddenMoviesAndAccessibleMoves() {
        let store = arrangedStore()
        store.selectLibrarySort(.custom)
        store.libraryQuery = "a"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws"])
        store.moveCustomMovie("jaws", by: -1)
        store.libraryQuery = ""
        XCTAssertEqual(store.libraryResults.map(\.id), ["jaws", "arrival", "unowned"])
        store.libraryFormats = [.vhs]
        XCTAssertTrue(store.libraryResults.isEmpty)
        store.selectLibrarySort(.titleDescending)
        store.selectLibrarySort(.custom)
        store.libraryFormats = []
        XCTAssertEqual(store.libraryResults.map(\.id), ["jaws", "arrival", "unowned"])
        store.moveCustomMovie("not-owned", to: "arrival")
        XCTAssertEqual(store.libraryResults.map(\.id), ["jaws", "arrival", "unowned"])
    }

    func testCustomArrangementHandlesRemovedAndNewMoviesAfterRefresh() {
        let store = arrangedStore()
        store.moveCustomMovie("unowned", to: "arrival")
        let newMovie = Movie(id: "new", title: "A new film", year: 2026, palette: 0, synopsis: "")
        let replacement = CatalogStore(
            movies: [Fixtures.arrival, Fixtures.unowned, newMovie],
            copies: [Fixtures.arrival, Fixtures.unowned, newMovie].map {
                OwnedCopy(id: $0.id, libraryID: "personal", movieID: $0.id, format: .dvd)
            }, libraries: Fixtures.libraries, memberships: Fixtures.memberships,
            userID: "me", personalStates: [])
        store.replaceContents(from: replacement)
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned", "arrival", "new"])
        let later = Movie(
            id: "later", title: "A film added later", year: 2026, palette: 0, synopsis: "")
        let secondSnapshot = CatalogStore(
            movies: [Fixtures.arrival, Fixtures.unowned, newMovie, later],
            copies: [Fixtures.arrival, Fixtures.unowned, newMovie, later].map {
                OwnedCopy(id: $0.id, libraryID: "personal", movieID: $0.id, format: .dvd)
            }, libraries: Fixtures.libraries, memberships: Fixtures.memberships,
            userID: "me", personalStates: [])
        store.replaceContents(from: secondSnapshot)
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned", "arrival", "new", "later"])
        store.selectLibrarySort(.custom)
        store.moveCustomMovie("new", by: -1)
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned", "new", "arrival", "later"])
    }

}
