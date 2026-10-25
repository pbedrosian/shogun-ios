import XCTest
@testable import Shogun

final class ModelTests: XCTestCase {
    func testPersonalStateDefaultsToUnwatchedAndUnrated() throws {
        let state = PersonalMovieState(userID: "me", movieID: "movie")
        XCTAssertFalse(state.watched)
        XCTAssertNil(state.rating)
        XCTAssertEqual(state.userID, "me")
        XCTAssertEqual(state.movieID, "movie")
    }

    func testFormatsHaveStableUniqueIdentifiers() throws {
        XCTAssertEqual(MovieFormat.allCases.map(\.rawValue), ["VHS", "DVD", "Blu-ray", "4K UHD", "Digital"])
        XCTAssertEqual(Set(MovieFormat.allCases.map(\.id)).count, 5)
    }

    func testEveryFormatRoundTripsThroughJSON() throws {
        for format in MovieFormat.allCases {
            let data = try JSONEncoder().encode(format)
            XCTAssertEqual(try JSONDecoder().decode(MovieFormat.self, from: data), format)
        }
    }

    func testUnknownFormatFailsDecoding() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(MovieFormat.self, from: Data("\"LaserDisc\"".utf8)))
    }

    func testMovieEqualityAndHashing() throws {
        let same = Movie(id: "arrival", title: "Arrival", year: 2016, symbol: "moon", palette: 0, synopsis: "First contact")
        XCTAssertEqual(Fixtures.arrival, same)
        XCTAssertEqual(Set([Fixtures.arrival, same, Fixtures.jaws]).count, 2)
    }

}
