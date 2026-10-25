import XCTest

@MainActor
final class AppFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(dark: Bool = false, accessibilityText: Bool = false) {
        if dark { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["Library view options"].waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Expected a reachable control: \(element)")
    }

    private func zoom(_ action: String) {
        app.buttons["library.viewOptions"].tap()
        app.buttons[action].tap()
    }

    func testLibrarySearchAndViewingDiaryPersistAcrossTabs() {
        launch()
        let query = app.textFields["Search this library"]
        query.tap()
        query.typeText("no matching title")
        XCTAssertFalse(app.buttons["library.movie.arrival-2016"].exists)
        app.buttons["Clear search"].tap()
        query.typeText("Arrival")
        let arrival = app.buttons["library.movie.arrival-2016"]
        XCTAssertTrue(arrival.waitForExistence(timeout: 5))
        arrival.tap()
        XCTAssertTrue(app.navigationBars["Movie"].waitForExistence(timeout: 5))

        let watched = app.switches["Watched"]
        reveal(watched)
        XCTAssertEqual(watched.value as? String, "1")
        watched.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(watched.waitForExistence(timeout: 3))
        XCTAssertEqual(watched.value as? String, "0")
        watched.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        reveal(app.buttons["Rate 4 of 5 stars"])
        app.buttons["Rate 4 of 5 stars"].tap()
        XCTAssertTrue(app.staticTexts["4 of 5 stars"].exists)
        app.buttons["Clear rating"].tap()
        XCTAssertTrue(app.staticTexts["Not rated"].exists)
        app.buttons["Rate 3 of 5 stars"].tap()
        XCTAssertTrue(app.staticTexts["3 of 5 stars"].exists)

        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Arrival")
        app.buttons["search.movie.arrival-2016"].tap()
        reveal(app.staticTexts["3 of 5 stars"])
        XCTAssertTrue(app.staticTexts["3 of 5 stars"].exists)
    }

    func testSearchNoResultsAndProfileInDarkAppearance() {
        launch(dark: true)
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("no matching title")
        XCTAssertTrue(app.descendants(matching: .any)["search.empty"].firstMatch.waitForExistence(timeout: 5))
        // Native searchable clear restores the catalog without changing tabs.
        search.buttons.firstMatch.tap()
        search.typeText("1927")
        let metropolis = app.buttons["search.movie.metropolis-1927"]
        XCTAssertTrue(metropolis.waitForExistence(timeout: 5))
        metropolis.tap()
        XCTAssertTrue(app.navigationBars["Movie"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Not rated"])
        XCTAssertTrue(app.staticTexts["Not rated"].exists)

        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Demo account"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["All content is local sample data. No account is connected."])
        XCTAssertTrue(app.staticTexts["All content is local sample data. No account is connected."].exists)
    }

    func testAddCopyCanCancelThenSaveIntoSelectedLibrary() {
        launch()
        app.buttons["library.selector"].tap()
        app.buttons["Family Collection"].tap()
        app.buttons["Add movie"].tap()
        XCTAssertTrue(app.navigationBars["Add Movie"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["addMovie.alreadyOwned"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["Add Movie"].exists)
        app.buttons["Add movie"].tap()
        app.buttons["Save"].tap()
        XCTAssertFalse(app.navigationBars["Add Movie"].exists)
        app.buttons["library.movie.arrival-2016"].tap()
        reveal(app.staticTexts["2 copies"])
        XCTAssertTrue(app.staticTexts["2 copies"].exists)
    }

    func testDensityMenuAndPinchShareStateAndKeepNavigationUsable() {
        launch()
        let menu = app.buttons["library.viewOptions"]
        XCTAssertEqual(menu.value as? String, "3")
        zoom("Zoom In")
        XCTAssertEqual(menu.value as? String, "2")
        for _ in 0..<3 { zoom("Zoom Out") }
        XCTAssertEqual(menu.value as? String, "5")
        let scroll = app.scrollViews["library.scroll"]
        scroll.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(app.navigationBars["Movie"].exists == false)
        XCTAssertNotEqual(menu.value as? String, "5")
        zoom("Zoom Out")
        XCTAssertTrue(menu.exists)
        app.buttons["library.movie.arrival-2016"].tap()
        XCTAssertTrue(app.navigationBars["Movie"].waitForExistence(timeout: 5))
    }

    func testAccessibilityTextKeepsTwoColumns() {
        launch(dark: true, accessibilityText: true)
        let menu = app.buttons["library.viewOptions"]
        XCTAssertEqual(menu.value as? String, "2")
        menu.tap()
        XCTAssertFalse(app.buttons["Zoom In"].isEnabled)
        XCTAssertFalse(app.buttons["Zoom Out"].isEnabled)
    }
}
