import XCTest

@MainActor
final class LibraryScrollUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    private func launch() {
        app.launchArguments.append("-shogun-demo")
        app.launch()
        XCTAssertTrue(app.buttons["library.viewOptions"].waitForExistence(timeout: 10))
    }

    func testArrangingLocksColumnsDuringPinch() {
        launch()
        let menu = app.buttons["library.viewOptions"]
        let columns = menu.value as? String
        menu.tap()
        app.buttons["Custom"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.movie."))
            .element(boundBy: 0).press(forDuration: 0.5)
        let done = app.buttons["library.arrange.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        app.scrollViews["library.scroll"].pinch(withScale: 0.5, velocity: -1)
        XCTAssertTrue(done.exists)
        XCTAssertEqual(menu.value as? String, columns)
        done.tap()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 5))
        app.scrollViews["library.scroll"].pinch(withScale: 2, velocity: 1)
        XCTAssertNotEqual(menu.value as? String, columns)
    }

    func testHeldMovieScrollsDownAndBackToTopWithoutChangingColumns() {
        app.launchArguments.append("-shogun-long-grid")
        launch()
        app.buttons["library.viewOptions"].tap()
        app.buttons["Custom"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
        let identifier = "library.movie.scroll-movie-000"
        app.buttons[identifier].press(forDuration: 0.5)
        let done = app.buttons["library.arrange.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["library.scroll"]
        let source = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let columns = app.buttons["library.viewOptions"].value as? String
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let bottom = origin.withOffset(
            CGVector(dx: scroll.frame.minX + 30, dy: done.frame.minY - 18))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.5, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 4)
        XCTAssertTrue(done.exists)
        XCTAssertEqual(app.buttons["library.viewOptions"].value as? String, columns)
        let visible = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library.movie.scroll-movie-")
        )
        .allElementsBoundByIndex.filter(\.isHittable)
        let latest = visible.compactMap { Int($0.identifier.suffix(3)) }.max() ?? 0
        XCTAssertGreaterThan(
            latest, 12, "Holding at the bottom must reveal movies beyond the first page")
        let startY =
            (max(source.frame.minY, scroll.frame.minY + 8)
                + min(source.frame.maxY, done.frame.minY - 8)) / 2
        let start = origin.withOffset(CGVector(dx: source.frame.midX, dy: startY))
        let top = origin.withOffset(
            CGVector(dx: scroll.frame.minX + 30, dy: scroll.frame.minY + 12))
        start.press(forDuration: 0.5, thenDragTo: top, withVelocity: .fast, thenHoldForDuration: 6)
        XCTAssertEqual(app.buttons["library.viewOptions"].value as? String, columns)
        done.tap()
        let tiles = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library.movie."))
        XCTAssertEqual(tiles.element(boundBy: 0).identifier, identifier)
        scroll.swipeUp()
        XCTAssertFalse(app.buttons[identifier].isHittable)
        let reachable = tiles.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(reachable)
        reachable?.tap()
        XCTAssertTrue(app.navigationBars["Movie"].waitForExistence(timeout: 5))
    }

}
