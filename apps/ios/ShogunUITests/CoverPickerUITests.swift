import XCTest

@MainActor final class CoverPickerUITests: XCTestCase {
    private var app: XCUIApplication!
    private func signIn(extra: [String] = [], owned: Bool = true) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-shogun-auth-ui"] + (owned ? ["-cover-owned"] : []) + extra
        app.launchEnvironment["SHOGUN_UI_PREFERENCES_SUITE"] = "cover-tests-\(UUID().uuidString)"
        app.launch()
        if app.buttons["auth.emailMethod"].exists {
            app.buttons["auth.emailMethod"].tap()
        }
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("owner@shogun.test")
        let password = app.secureTextFields["auth.password"]
        password.tap()
        password.typeText("valid-password")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 10))
    }
    private func openCoverEditor() {
        let actions = app.buttons["movie.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        let cover = app.buttons["movie.changeCover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
    }
    private func openPicker(extra: [String] = []) {
        signIn(extra: extra)
        let movie = app.buttons["library.movie.30000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(movie.waitForExistence(timeout: 10))
        movie.tap()
        openCoverEditor()
        XCTAssertTrue(app.buttons["cover.default"].waitForExistence(timeout: 5))
    }
    func testChooseCoverFailureRetryAndReset() {
        openPicker(extra: ["-collection-save-error"])
        let option = app.buttons["cover.option.0"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        app.buttons["cover.save"].tap()
        XCTAssertTrue(app.staticTexts["collection.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(option.isSelected)
        app.buttons["cover.save"].tap()
        XCTAssertTrue(app.buttons["movie.actions"].waitForExistence(timeout: 5))
        openCoverEditor()
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertTrue(option.isSelected)
        app.buttons["cover.default"].tap()
        app.buttons["cover.save"].tap()
        XCTAssertTrue(app.buttons["movie.actions"].waitForExistence(timeout: 5))
        openCoverEditor()
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertFalse(option.isSelected)
    }
    func testCancelAndEmptyPickerInDarkLargeText() {
        openPicker(extra: [
            "-cover-empty", "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCTAssertTrue(app.staticTexts["No alternate covers"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cover.save"].isEnabled)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Cover picker — dark accessibility text"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["movie.actions"].waitForExistence(timeout: 5))
    }
    func testUnavailableCoversStillAllowDefaultReset() {
        openPicker(extra: ["-cover-load-error"])
        XCTAssertTrue(app.buttons["cover.retry"].waitForExistence(timeout: 5))
        app.buttons["cover.default"].tap()
        XCTAssertTrue(app.buttons["cover.save"].isEnabled)
        app.buttons["cover.save"].tap()
        XCTAssertTrue(app.buttons["movie.actions"].waitForExistence(timeout: 5))
    }
    func testCancellingSelectedCoverPreservesArtwork() {
        openPicker()
        let choice = app.buttons["cover.option.1"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertTrue(choice.isSelected)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Cover picker — alternate posters"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Cancel"].tap()
        openCoverEditor()
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertFalse(choice.isSelected)
    }
    private func startAdding(extra: [String] = [], owned: Bool = false) {
        signIn(extra: extra, owned: owned)
        app.buttons["Add movie"].tap()
        let query = app.textFields["addMovie.search"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("Arrival\n")
        let movie = app.buttons["addMovie.result.329865"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        movie.tap()
        let choose = app.buttons["addMovie.chooseCover"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        let option = app.buttons["cover.option.1"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        app.buttons["cover.save"].tap()
        XCTAssertTrue(app.buttons["addMovie.chooseCover"].waitForExistence(timeout: 5))
    }
    func testAddMovieKeepsChosenCoverAfterFailedSave() {
        startAdding(extra: ["-collection-save-error"])
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Add Movie — chosen cover before saving"
        image.lifetime = .keepAlways
        add(image)
        let quantity = app.buttons["addMovie.quantity.4K UHD-Increment"]
        for _ in 0..<12 {
            if quantity.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(quantity.isHittable)
        quantity.tap()
        app.buttons["addMovie.save"].tap()
        XCTAssertTrue(app.staticTexts["collection.error"].waitForExistence(timeout: 5))
        app.buttons["addMovie.save"].tap()
        let movie = app.buttons["library.movie.30000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        movie.tap()
        openCoverEditor()
        let chosen = app.buttons["cover.option.1"]
        XCTAssertTrue(chosen.waitForExistence(timeout: 5))
        XCTAssertTrue(chosen.isSelected)
    }
    func testCancellingAddDoesNotChangeExistingCover() {
        startAdding(owned: true)
        app.buttons["Cancel"].tap()
        let movie = app.buttons["library.movie.30000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        movie.tap()
        XCTAssertTrue(app.staticTexts["1 copy"].exists)
        openCoverEditor()
        let choice = app.buttons["cover.option.1"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertFalse(choice.isSelected)
    }
    func testMovieMenuUpdatesCountAndConfirmsRemoval() {
        signIn()
        app.buttons["library.movie.30000000-0000-0000-0000-000000000001"].tap()
        app.buttons["movie.actions"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Movie detail — actions menu"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["movie.updateCount"].tap()
        let increment = app.buttons["editCopies.4K UHD-Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        increment.tap()
        app.buttons["editCopies.save"].tap()
        XCTAssertTrue(app.staticTexts["2 copies"].waitForExistence(timeout: 5))
        app.buttons["movie.actions"].tap()
        app.buttons["movie.removeFromCollection"].tap()
        XCTAssertTrue(app.alerts["Remove from collection?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["2 copies"].exists)
        app.buttons["movie.actions"].tap()
        app.buttons["movie.removeFromCollection"].tap()
        app.alerts.buttons["Remove"].tap()
        XCTAssertTrue(app.staticTexts["No movies yet"].waitForExistence(timeout: 5))
    }
}
