import XCTest

@testable import Shogun

final class LibraryGridScrollPolicyTests: XCTestCase {
    func testGridEdgeScrollAcceleratesNearViewportEdges() {
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: 400, height: 800), 0)
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: 0, height: 800), -480)
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: 800, height: 800), 480)
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: 40, height: 800), -240)
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: 760, height: 800), 240)
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: -1, height: 800), -480)
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: 801, height: 800), 480)
        XCTAssertEqual(LibraryGridScrollPolicy.velocity(y: 0, height: 0), 0)
    }

    func testGridDropSelectionUsesVisibleTilesIncludingGapsAndEdges() {
        let frames = [
            "hidden": CGRect(x: 0, y: -200, width: 100, height: 100),
            "below": CGRect(x: 0, y: 500, width: 100, height: 100),
            "left": CGRect(x: 0, y: 100, width: 100, height: 100),
            "right": CGRect(x: 120, y: 100, width: 100, height: 100),
        ]
        let viewport = CGRect(x: 0, y: 0, width: 240, height: 400)
        for point in [CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 150), CGPoint(x: 10, y: 390)] {
            XCTAssertEqual(
                LibraryGridScrollPolicy.target(at: point, frames: frames, viewport: viewport),
                "left")
        }
        XCTAssertEqual(
            LibraryGridScrollPolicy.target(
                at: CGPoint(x: 115, y: 150), frames: frames, viewport: viewport), "right")
        XCTAssertNil(LibraryGridScrollPolicy.target(at: .zero, frames: [:], viewport: viewport))
    }

}
