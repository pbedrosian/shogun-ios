import XCTest

@MainActor
final class AppFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(dark: Bool = false, accessibilityText: Bool = false) {
        app.launchArguments += ["-shogun-demo"]
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
        app.buttons["View Options"].tap()
        app.buttons[action].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
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


    func testViewOptionsStayOpenForSortFormatClearAndRepeatedZoom() {
        launch()
        let menu = app.buttons["library.viewOptions"]
        menu.tap()
        app.buttons["Title Z–A"].tap()
        XCTAssertTrue(app.buttons["Title A–Z"].isHittable)
        app.buttons["Formats"].tap()
        app.buttons["DVD"].tap()
        XCTAssertTrue(app.buttons["VHS"].isHittable)
        app.buttons["VHS"].tap()
        app.buttons["Clear filters"].firstMatch.tap()
        XCTAssertTrue(app.buttons["DVD"].isHittable)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
        menu.tap()
        app.buttons["View Options"].tap()
        app.buttons["Zoom Out"].tap()
        XCTAssertTrue(app.buttons["Zoom In"].isHittable)
        app.buttons["Zoom Out"].tap()
        XCTAssertEqual(menu.value as? String, "5")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
        XCTAssertTrue(menu.isHittable)
    }

    func testAccessibilityTextKeepsTwoColumns() {
        launch(dark: true, accessibilityText: true)
        let menu = app.buttons["library.viewOptions"]
        XCTAssertEqual(menu.value as? String, "2")
        menu.tap()
        app.buttons["View Options"].tap()
        XCTAssertFalse(app.buttons["Zoom In"].isEnabled)
        XCTAssertFalse(app.buttons["Zoom Out"].isEnabled)
    }

}

@MainActor final class AuthFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(dark: Bool = false, large: Bool = false, extra: [String] = []) {
        app.launchArguments = ["-shogun-auth-ui"] + extra
        if dark { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 10))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func fill(_ password: String) {
        let email = app.textFields["auth.email"]; email.tap(); email.typeText("owner@shogun.test")
        let field = app.secureTextFields["auth.password"]; field.tap(); field.typeText(password)
    }
    func testSignInFailureSuccessAndSignOut() {
        launch(); XCTAssertTrue(app.staticTexts["auth.brand"].exists)
        XCTAssertFalse(app.buttons["auth.demo"].exists)
        XCTAssertFalse(app.staticTexts["Your movies.\nYour collection."].exists)
        fill("invalid-password"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["auth.error"].waitForExistence(timeout: 5))
        let field = app.secureTextFields["auth.password"]; field.tap(); field.typeText("valid-password"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Profile"].tap(); XCTAssertEqual(app.staticTexts["auth.accountEmail"].label, "owner@shogun.test")
        reveal(app.buttons["auth.signOut"]); app.buttons["auth.signOut"].tap(); XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 5))
    }
    func testCreateAccountConfirmationAndRecovery() {
        launch(dark: true); let create = app.buttons["auth.createAccount"]; reveal(create); create.tap()
        fill("new-password")
        app.buttons["auth.submit"].tap(); XCTAssertTrue(app.staticTexts["auth.validation"].waitForExistence(timeout: 5))
        let confirm = app.secureTextFields["auth.confirmPassword"]; reveal(confirm); confirm.tap(); confirm.typeText("new-password")
        app.buttons["auth.submit"].tap(); XCTAssertTrue(app.staticTexts["auth.message"].waitForExistence(timeout: 5))
        let back = app.buttons["auth.backToSignIn"]; reveal(back); back.tap()
        app.buttons["auth.forgotPassword"].tap(); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["auth.message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["auth.message"].label.contains("If this email"))
    }
    func testCancellationAndBackNavigation() {
        launch(); fill("slow-password"); app.buttons["auth.submit"].tap()
        let cancel = app.buttons["auth.cancel"]; XCTAssertTrue(cancel.waitForExistence(timeout: 5)); reveal(cancel); cancel.tap()
        XCTAssertTrue(app.buttons["auth.submit"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["auth.accountEmail"].exists)
        let create = app.buttons["auth.createAccount"]; reveal(create); create.tap()
        let back = app.buttons["auth.backToSignIn"]; reveal(back); back.tap()
        XCTAssertTrue(app.buttons["auth.forgotPassword"].waitForExistence(timeout: 5))
    }
#if SHOGUN_LIVE_AUTH
    func testLiveLocalSignInRelaunchAndSignOut() {
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 15))
        fill("Shogun-local-only-25!"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Profile"].tap(); XCTAssertEqual(app.staticTexts["auth.accountEmail"].label, "owner@shogun.test")
        reveal(app.buttons["auth.signOut"]); app.buttons["auth.signOut"].tap(); XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 10))
    }
#endif
    func testProfileHeaderAndAccountDeletionConfirmation() {
        launch(); fill("valid-password"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Shogun account"].exists)
        XCTAssertTrue(app.staticTexts["Signed in"].exists)
        XCTAssertEqual(app.staticTexts["auth.accountEmail"].label, "owner@shogun.test")
        let delete = app.buttons["auth.deleteAccount"]; reveal(delete); delete.tap()
        app.navigationBars.buttons["Cancel"].tap(); XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let password = app.secureTextFields["auth.deletePassword"]; password.tap(); password.typeText("invalid-password\n")
        let request = app.buttons["auth.requestDeletion"]; reveal(request); request.tap()
        app.alerts.buttons["Delete permanently"].tap()
        XCTAssertTrue(app.staticTexts["auth.deleteError"].waitForExistence(timeout: 5))
        password.tap(); password.typeText("valid-password\n"); reveal(request); request.tap()
        app.alerts.buttons["Delete permanently"].tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["auth.message"].label.contains("deleted"))
    }
    func testRecoveryPasswordScreen() {
        app.launchArguments = ["-shogun-auth-ui", "-shogun-auth-recovery", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        let password = app.secureTextFields["auth.newPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 10)); password.tap(); password.typeText("new-password")
        app.buttons["auth.updatePassword"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
    }
    func testLargeTextAndPasswordVisibility() {
        launch(dark: true, large: true)
        let password = app.secureTextFields["auth.password"]; reveal(password); password.tap(); password.typeText("visible-test")
        let toggle = app.buttons["auth.password.visibility"]; reveal(toggle); toggle.tap()
        XCTAssertEqual(app.textFields["auth.password"].value as? String, "visible-test")
        toggle.tap(); XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        toggle.tap() // Switching forms must restore secure entry even after showing a password.
        let create = app.buttons["auth.createAccount"]; reveal(create); create.tap()
        XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        reveal(app.secureTextFields["auth.confirmPassword"])
        XCTAssertFalse(app.buttons["auth.demo"].exists)
    }
    func testCollectionLoadFailureRetryAndNoLibraryCreation() {
        launch(extra: ["-collection-load-error", "-collection-no-libraries"])
        fill("valid-password"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["collection.error"].waitForExistence(timeout: 5))
        app.buttons["collection.refresh"].tap()
        let create = app.buttons["Create personal library"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No movies yet"].exists)
    }
    func testCollectionFailedCopySaveKeepsFormThenDiaryPersistsAcrossTabs() {
        launch(extra: ["-collection-save-error"])
        fill("valid-password")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["collection.refresh"].exists)
        app.buttons["Add movie"].tap()
        let queryField = app.textFields["addMovie.search"]
        XCTAssertTrue(queryField.waitForExistence(timeout: 5))
        queryField.tap()
        queryField.typeText("Arrival\n")
        let selected = app.buttons["addMovie.result.329865"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        selected.tap()
        let quantity = app.buttons["addMovie.quantity.Blu-ray-Increment"]
        revealForm(quantity)
        quantity.tap()
        let saveMovie = app.buttons["addMovie.save"]
        XCTAssertTrue(saveMovie.waitForExistence(timeout: 5))
        saveMovie.tap()
        XCTAssertTrue(app.staticTexts["collection.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add Movie"].exists)
        app.navigationBars.buttons["Save"].tap()
        let film = app.buttons["library.movie.30000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(film.waitForExistence(timeout: 5))
        film.tap()
        let watched = app.switches["Watched"]
        reveal(watched)
        watched.tap()
        let star = app.buttons["Rate 4 of 5 stars"]
        reveal(star)
        star.tap()
        let save = app.buttons["collection.saveDiary"]
        reveal(save)
        save.tap()
        XCTAssertTrue(app.staticTexts["4 of 5 stars"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Search"].tap()
        let query = app.searchFields["Search movies"]
        query.tap()
        query.typeText("Arrival")
        let result = app.buttons["discovery.movie.329865"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let owned = app.buttons["discovery.owned"]
        XCTAssertTrue(owned.waitForExistence(timeout: 5))
        reveal(owned)
        owned.tap()
        XCTAssertTrue(app.staticTexts["4 of 5 stars"].waitForExistence(timeout: 5))
    }
    private func revealForm(_ element: XCUIElement, forTyping: Bool = false) {
        let safeTop = app.frame.minY + app.frame.height * 0.25
        let safeBottom = app.frame.minY + app.frame.height * 0.7
        for _ in 0..<18 {
            // Hittable fields can still sit under the navigation bar after keyboard dismissal.
            // Bring the control into the form's clear area before tapping or typing.
            if element.isHittable {
                if !forTyping { return }
                let center = element.frame.midY
                if center >= safeTop && center <= safeBottom { return }
            }
            let isAbove = forTyping && element.exists && element.frame.midY < safeTop
            let destination = isAbove ? 0.8 : 0.2
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
                .press(
                    forDuration: 0.05,
                    thenDragTo: app.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.94, dy: destination)))
        }
        XCTAssertTrue(element.isHittable)
        if forTyping {
            XCTAssertGreaterThanOrEqual(element.frame.midY, safeTop)
            XCTAssertLessThanOrEqual(element.frame.midY, safeBottom)
        }
    }
    func testManualMovieQuantityAndMetadataInDarkLargeText() {
        launch(dark: true, large: true)
        fill("valid-password")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.buttons["Add movie"].tap()
        let manual = app.buttons["addMovie.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        let title = app.textFields["addMovie.title"]
        revealForm(title, forTyping: true)
        title.tap()
        title.typeText("Festival Film")
        app.buttons["addMovie.keyboardDone"].tap()
        let director = app.textFields["addMovie.director"]
        revealForm(director, forTyping: true)
        director.tap()
        director.typeText("A Director")
        app.buttons["addMovie.keyboardDone"].tap()
        let synopsis =
            app.textViews["addMovie.synopsis"].exists
            ? app.textViews["addMovie.synopsis"] : app.textFields["addMovie.synopsis"]
        revealForm(synopsis, forTyping: true)
        synopsis.tap()
        synopsis.typeText("A festival story")
        app.buttons["addMovie.keyboardDone"].tap()
        let genres = app.textFields["addMovie.genres"]
        revealForm(genres, forTyping: true)
        genres.tap()
        genres.typeText("Drama, Mystery")
        app.buttons["addMovie.keyboardDone"].tap()
        let increment = app.buttons["addMovie.quantity.Blu-ray-Increment"]
        revealForm(increment)
        increment.tap()
        increment.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Manual movie dark large text"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["addMovie.save"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        let film = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Festival Film"))
            .firstMatch
        reveal(film)
        film.tap()
        XCTAssertTrue(app.staticTexts["Festival Film"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A festival story"].exists)
        let savedDirector = app.descendants(matching: .any).matching(identifier: "movie.director")
            .firstMatch
        XCTAssertEqual(savedDirector.value as? String, "A Director")
        XCTAssertTrue(app.staticTexts["2 copies"].exists)
        let edit = app.buttons["movie.editCopies.20000000-0000-0000-0000-000000000001"]
        revealForm(edit)
        edit.tap()
        let decrease = app.buttons["editCopies.Blu-ray-Decrement"]
        revealForm(decrease)
        decrease.tap()
        let dvd = app.buttons["editCopies.DVD-Increment"]
        dvd.tap()
        app.buttons["editCopies.save"].tap()
        XCTAssertTrue(app.staticTexts["DVD · Blu-ray"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 copies"].exists)
    }
    func testAddMovieSearchAndDetailsRetryThenCancel() {
        launch(extra: ["-discovery-error", "-discovery-detail-error"])
        fill("valid-password")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.buttons["Add movie"].tap()
        let query = app.textFields["addMovie.search"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("Arrival\n")
        let retry = app.buttons["Retry search"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        let result = app.buttons["addMovie.result.329865"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let detailRetry = app.buttons["Retry details"]
        reveal(detailRetry)
        detailRetry.tap()
        let save = app.buttons["addMovie.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let quantity = app.buttons["addMovie.quantity.Blu-ray-Increment"]
        revealForm(quantity)
        quantity.tap()
        let ready = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save)
        wait(for: [ready], timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Selected provider movie"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["No movies yet"].waitForExistence(timeout: 5))

    }
    func testCollectionDefaultAndCreateLibrary() {
        launch(); fill("valid-password"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Profile"].tap()
        XCTAssertFalse(app.staticTexts["Movie information"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Compact profile - light"
        preview.lifetime = .keepAlways
        add(preview)
        app.buttons["About & credits"].tap()
        XCTAssertTrue(app.staticTexts["This product uses the TMDB API but is not endorsed or certified by TMDB."].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Profile"].tap()
        app.buttons["profile.manageLibraries"].tap()
        let personal = app.buttons["profile.defaultLibrary.20000000-0000-0000-0000-000000000001"]
        personal.tap()
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        let selected = NSPredicate(format: "value == %@", "Default library")
        expectation(for: selected, evaluatedWith: personal)
        waitForExpectations(timeout: 5)
        let create = app.buttons["Create library"]; reveal(create); create.tap()
        let name = app.textFields["collection.libraryName"]; name.tap(); name.typeText("Family films")
        app.navigationBars.buttons["Create"].tap()
        XCTAssertTrue(app.buttons["Family films"].waitForExistence(timeout: 5))
        app.buttons["Family films"].tap()
        expectation(for: selected, evaluatedWith: app.buttons["Family films"])
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons["Profile"].tap()
        XCTAssertTrue(app.otherElements.containing(.staticText, identifier: "Family films").firstMatch.waitForExistence(timeout: 5))
        app.buttons["profile.manageLibraries"].tap()
        XCTAssertEqual(personal.value as? String, "Select as default")
        XCTAssertEqual(app.buttons["Family films"].value as? String, "Default library")
        app.navigationBars.buttons["Profile"].tap()
        app.buttons["profile.openLibrary.20000000-0000-0000-0000-000000000001"].tap()
        let librarySelector = app.buttons["library.selector"]
        XCTAssertTrue(librarySelector.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)
        XCTAssertTrue(librarySelector.label.contains("My Library"))
        app.tabBars.buttons["Profile"].tap()
        app.buttons["profile.manageLibraries"].tap()
        XCTAssertEqual(app.buttons["Family films"].value as? String, "Default library")
    }

    func testProfileLibraryManagementInDarkLargeText() {
        launch(dark: true, large: true)
        fill("valid-password")
        reveal(app.buttons["auth.submit"])
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Profile"].tap()
        XCTAssertEqual(app.staticTexts["auth.accountEmail"].label, "owner@shogun.test")
        XCTAssertFalse(app.staticTexts["Movie information"].exists)
        let profile = XCTAttachment(screenshot: app.screenshot())
        profile.name = "Compact profile - dark large text"
        profile.lifetime = .keepAlways
        add(profile)
        let manage = app.buttons["profile.manageLibraries"]
        reveal(manage)
        manage.tap()
        let personal = app.buttons["profile.defaultLibrary.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        reveal(personal)
        personal.tap()
        expectation(for: NSPredicate(format: "value == %@", "Default library"), evaluatedWith: personal)
        waitForExpectations(timeout: 5)
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "Default library picker - dark large text"
        picker.lifetime = .keepAlways
        add(picker)
    }

    func testLiveDiscoveryBlankSearchPaginationAndDetails() {
        launch(dark: true, large: true); fill("valid-password"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Search movies"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discovery.movie.329865"].exists)
        XCTAssertFalse(app.staticTexts["discovery.empty"].exists)
        field.tap(); field.typeText("Arrival")
        let arrival = app.buttons["discovery.movie.329865"]
        XCTAssertTrue(arrival.waitForExistence(timeout: 5))
        let more = app.buttons["discovery.more"]; reveal(more); more.tap()
        XCTAssertTrue(app.buttons["discovery.movie.11"].waitForExistence(timeout: 5))
        reveal(arrival); arrival.tap()
        XCTAssertTrue(app.scrollViews["discovery.detail"].waitForExistence(timeout: 5))
        let director = app.descendants(matching: .any)["discovery.director"].firstMatch; reveal(director)
        XCTAssertTrue(director.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(arrival.waitForExistence(timeout: 5))
        field.tap(); field.buttons["Clear text"].tap()
        XCTAssertFalse(arrival.exists)
        field.typeText("no matches")
        XCTAssertTrue(app.descendants(matching: .any)["discovery.empty"].firstMatch.waitForExistence(timeout: 5))
    }
    func testLiveDiscoverySearchAndDetailFailuresRetry() {
        launch(extra: ["-discovery-error", "-discovery-detail-error"])
        fill("valid-password"); app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.buttons["library.selector"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Search movies"]; field.tap(); field.typeText("Arrival")
        XCTAssertTrue(app.staticTexts["discovery.error"].waitForExistence(timeout: 5))
        app.buttons["discovery.retry"].tap()
        let movie = app.buttons["discovery.movie.329865"]; XCTAssertTrue(movie.waitForExistence(timeout: 5)); movie.tap()
        let error = app.staticTexts["discovery.detailError"]; XCTAssertTrue(error.waitForExistence(timeout: 5)); reveal(error)
        let retry = app.buttons["discovery.detailRetry"]; reveal(retry); retry.tap()
        let director = app.descendants(matching: .any)["discovery.director"].firstMatch; reveal(director)
        XCTAssertTrue(director.waitForExistence(timeout: 5))
    }

}
