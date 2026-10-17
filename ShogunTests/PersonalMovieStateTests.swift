import XCTest
@testable import Shogun

final class PersonalMovieStateTests: XCTestCase {
    func testNewMovieIsUnwatchedAndUnrated() throws {
        let state = Fixtures.store().state(for: Fixtures.arrival)
        XCTAssertEqual(state.userID, "me")
        XCTAssertEqual(state.movieID, "arrival")
        XCTAssertFalse(state.watched)
        XCTAssertNil(state.rating)
    }

    func testSeededStateIsLoadedForCurrentUserOnly() throws {
        let states = [PersonalMovieState(userID: "other", movieID: "arrival", watched: true, rating: 1), PersonalMovieState(userID: "me", movieID: "arrival", watched: true, rating: 4)]
        XCTAssertEqual(Fixtures.store(states: states).state(for: Fixtures.arrival).rating, 4)
    }

    func testWatchedCanBeSetAndClearedWithoutChangingRating() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, watched: true, rating: 4)
        store.update(Fixtures.arrival, watched: false)
        XCTAssertFalse(store.state(for: Fixtures.arrival).watched)
        XCTAssertEqual(store.state(for: Fixtures.arrival).rating, 4)
    }

    func testEveryValidRatingIsPreserved() throws {
        let store = Fixtures.store()
        for rating in 1...5 {
            store.update(Fixtures.arrival, rating: rating)
            XCTAssertEqual(store.state(for: Fixtures.arrival).rating, rating)
        }
    }

    func testRatingsClampAtBothBoundsIncludingIntegerExtremes() throws {
        let store = Fixtures.store()
        for rating in [Int.min, -1, 0] {
            store.update(Fixtures.arrival, rating: rating)
            XCTAssertEqual(store.state(for: Fixtures.arrival).rating, 1)
        }
        for rating in [6, 99, Int.max] {
            store.update(Fixtures.arrival, rating: rating)
            XCTAssertEqual(store.state(for: Fixtures.arrival).rating, 5)
        }
    }

    func testClearingRatingPreservesWatched() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, watched: true, rating: 5)
        store.update(Fixtures.arrival, clearRating: true)
        XCTAssertNil(store.state(for: Fixtures.arrival).rating)
        XCTAssertTrue(store.state(for: Fixtures.arrival).watched)
    }

    func testClearRatingTakesPrecedenceOverSuppliedRating() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, rating: 3, clearRating: true)
        XCTAssertNil(store.state(for: Fixtures.arrival).rating)
    }

    func testRatingOnlyUpdatePreservesWatched() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, watched: true)
        store.update(Fixtures.arrival, rating: 2)
        XCTAssertTrue(store.state(for: Fixtures.arrival).watched)
    }

    func testNoArgumentsPreserveExistingState() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, watched: true, rating: 3)
        store.update(Fixtures.arrival)
        XCTAssertTrue(store.state(for: Fixtures.arrival).watched)
        XCTAssertEqual(store.state(for: Fixtures.arrival).rating, 3)
    }

    func testStateFollowsMovieAcrossLibraries() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, watched: true, rating: 3)
        store.selectedLibraryID = "family"
        XCTAssertEqual(store.state(for: Fixtures.arrival).rating, 3)
        XCTAssertTrue(store.state(for: Fixtures.arrival).watched)
    }

    func testMovieStatesAreIndependent() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, watched: true, rating: 5)
        XCTAssertFalse(store.state(for: Fixtures.jaws).watched)
        XCTAssertNil(store.state(for: Fixtures.jaws).rating)
    }

    func testPersonalEditsDoNotChangeOwnership() throws {
        let store = Fixtures.store()
        let ids = store.copies.map(\.id)
        store.update(Fixtures.arrival, watched: true, rating: 1)
        XCTAssertEqual(store.copies.map(\.id), ids)
    }

    func testCurrentUserUpdateDoesNotInheritAnotherUsersWatchedState() throws {
        let states = [PersonalMovieState(userID: "other", movieID: "arrival", watched: true, rating: 2)]
        let store = Fixtures.store(states: states)
        store.update(Fixtures.arrival, rating: 4)
        XCTAssertEqual(store.state(for: Fixtures.arrival).rating, 4)
        XCTAssertFalse(store.state(for: Fixtures.arrival).watched)
    }

}
