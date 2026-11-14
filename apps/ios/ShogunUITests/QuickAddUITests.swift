import XCTest

@MainActor final class QuickAddUITests: XCTestCase {
    private var app: XCUIApplication!
    private func search(extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-shogun-auth-ui"] + extra
        app.launchEnvironment["SHOGUN_UI_PREFERENCES_SUITE"] = "quick-add-\(UUID().uuidString)"
        app.launch()
        let emailMethod = app.buttons["auth.emailMethod"]
        XCTAssertTrue(emailMethod.waitForExistence(timeout: 10))
        emailMethod.tap()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("owner@shogun.test")
        app.secureTextFields["auth.password"].tap()
        app.secureTextFields["auth.password"].typeText("valid-password")
        app.buttons["auth.submit"].tap()
        let tab = app.tabBars.buttons["Search"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let query = app.searchFields["Search movies"]
        query.tap()
        query.typeText("Arrival")
        XCTAssertTrue(app.buttons["discovery.movie.329865"].waitForExistence(timeout: 5))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func testResultAddPrefillsRetriesAndOffersAnotherCopy() {
        search(extra: ["-collection-save-error"])
        app.buttons["discovery.add.329865"].tap()
        XCTAssertTrue(app.navigationBars["Add Movie"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["addMovie.search"].exists)
        XCTAssertEqual(app.textFields["addMovie.title"].value as? String, "Arrival")
        XCTAssertFalse(app.buttons["addMovie.save"].isEnabled)
        let quantity = app.buttons["addMovie.quantity.Blu-ray-Increment"]
        reveal(quantity)
        quantity.tap()
        app.buttons["addMovie.save"].tap()
        XCTAssertTrue(app.staticTexts["collection.error"].waitForExistence(timeout: 5))
        app.buttons["addMovie.save"].tap()
        let addAgain = app.buttons["discovery.add.329865"]
        XCTAssertTrue(addAgain.waitForExistence(timeout: 5))
        XCTAssertTrue(addAgain.label.contains("another copy"))
        addAgain.tap()
        let ownership = app.staticTexts["addMovie.alreadyOwned"]
        reveal(ownership)
        XCTAssertTrue(ownership.label.contains("1 copies"))
        app.navigationBars["Add Movie"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["discovery.movie.329865"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields["Search movies"].value as? String, "Arrival")
    }
    func testDetailAddCancelInDarkLargeText() {
        search(extra: [
            "-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.buttons["discovery.movie.329865"].tap()
        let addButton = app.buttons["discovery.addToLibrary"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        reveal(addButton)
        addButton.tap()
        XCTAssertTrue(app.navigationBars["Add Movie"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Search detail — preselected Add Movie in dark large text"
        shot.lifetime = .keepAlways
        add(shot)
        let title = app.textFields["addMovie.title"]
        reveal(title)
        XCTAssertEqual(title.value as? String, "Arrival")
        app.navigationBars["Add Movie"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["discovery.addToLibrary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discovery.owned"].exists)
    }
    func testNoWritableLibraryDisablesSearchAdd() {
        search(extra: ["-collection-no-libraries"])
        let plus = app.buttons["discovery.add.329865"]
        XCTAssertFalse(plus.isEnabled)
        XCTAssertTrue(app.staticTexts["discovery.noWritableLibrary"].exists)
        app.buttons["discovery.movie.329865"].tap()
        let add = app.buttons["discovery.addToLibrary"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
    }
}
