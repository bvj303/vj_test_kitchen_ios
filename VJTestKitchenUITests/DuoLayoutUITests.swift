import XCTest

/// Screenshot + state-preservation pass over every main screen, for iPhone Duo's
/// configurations (and a regression check on standard iPhones and iPad).
///
/// XCTest can rotate the device but has no API for iPhone Duo's *pose* (closed,
/// open, partially folded) — that's set in Xcode's Device Hub. So run this suite
/// once per pose; each run covers the current pose in portrait and landscape.
/// It lives in its own scheme (`VJTestKitchenDuoUITests`, not run by CI) and
/// needs a signed-in account on whatever backend the app build points at —
/// credentials come from the environment and the suite skips without them:
///
///   TEST_RUNNER_DUO_UI_EMAIL=… TEST_RUNNER_DUO_UI_PASSWORD=… \
///   TEST_RUNNER_DUO_UI_SNAPSHOT_DIR=/path/for/pngs \
///   TEST_RUNNER_DUO_UI_CONFIG=closed \
///   xcodebuild test -scheme VJTestKitchenDuoUITests -destination '…iPhone Duo…'
///
/// Screenshots are attached to the result bundle and, when a snapshot dir is
/// given, also written there as `<config>-<orientation>-<screen>.png`.
final class DuoLayoutUITests: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        continueAfterFailure = true
        guard env["DUO_UI_EMAIL"] != nil, env["DUO_UI_PASSWORD"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_DUO_UI_EMAIL / TEST_RUNNER_DUO_UI_PASSWORD to run the layout pass.")
        }
        app = XCUIApplication()
        app.launch()
        try signInIfNeeded()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - Every screen, portrait and landscape

    func testEveryScreenInPortraitAndLandscape() throws {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let label = orientation == .portrait ? "portrait" : "landscape"
            for tab in ["Home", "Recipes", "Groceries", "AI Planner", "Calendar"] {
                openTab(tab)
                snapshot("\(label)-\(tab)")
                assertNothingCoveredOrOffscreen(screen: "\(label)-\(tab)")
            }
            openTab("Recipes")
            openFirstRecipe()
            snapshot("\(label)-RecipeDetail")
            assertNothingCoveredOrOffscreen(screen: "\(label)-RecipeDetail")
        }
    }

    // MARK: - State survives a size change

    /// Opening a recipe, then rotating (a size change like opening/closing iPhone
    /// Duo), must keep that recipe on screen — the old Recipes tab rebuilt its
    /// navigation container on size-class changes and dropped it.
    func testOpenRecipeSurvivesASizeChange() throws {
        XCUIDevice.shared.orientation = .portrait
        openTab("Recipes")
        let title = openFirstRecipe()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "“\(title)” should still be shown after rotating")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "“\(title)” should still be shown after rotating back")
    }

    /// Text typed into the AI Planner survives a size change.
    func testTypedTextSurvivesASizeChange() throws {
        XCUIDevice.shared.orientation = .portrait
        openTab("AI Planner")
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("spicy sausage dinner")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
        let value = (field.value as? String) ?? ""
        XCTAssertTrue(value.contains("spicy sausage dinner"), "typed text was lost: “\(value)”")
    }

    // MARK: - Helpers

    private func signInIfNeeded() throws {
        let email = app.textFields["Email"]
        guard email.waitForExistence(timeout: 8) else { return } // already signed in
        email.tap()
        email.typeText(env["DUO_UI_EMAIL"]!)
        let password = app.secureTextFields["Password"]
        password.tap()
        // Return submits the form (the password field's `.onSubmit` signs in); a
        // tap on Sign In straight after typing can land while the keyboard is
        // still animating and be dropped.
        password.typeText(env["DUO_UI_PASSWORD"]! + "\n")
        if !tabButton("Home").waitForExistence(timeout: 8), app.buttons["Sign In"].exists {
            app.buttons["Sign In"].tap()
        }
        XCTAssertTrue(tabButton("Home").waitForExistence(timeout: 20), "sign-in didn't reach the tabs")
        dismissOnboardingIfShown()
    }

    /// First launch shows the home-location prompt.
    private func dismissOnboardingIfShown() {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
    }

    private func tabButton(_ name: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[name]
        return inTabBar.exists ? inTabBar : app.buttons[name].firstMatch
    }

    private func openTab(_ name: String) {
        let button = tabButton(name)
        XCTAssertTrue(button.waitForExistence(timeout: 8), "\(name) tab not reachable")
        XCTAssertTrue(button.isHittable, "\(name) tab is on screen but not tappable")
        button.tap()
        _ = app.wait(for: .runningForeground, timeout: 1)
        sleep(2) // let the screen load its data before the snapshot
    }

    /// Opens the first recipe in the Recipes list; returns its title.
    @discardableResult
    private func openFirstRecipe() -> String {
        let cell = app.collectionViews.cells.firstMatch.exists ? app.collectionViews.cells.firstMatch : app.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "no recipes listed")
        let title = cell.staticTexts.firstMatch.label
        cell.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8), "recipe detail didn't open")
        sleep(1)
        return title
    }

    /// Every bar control (navigation bar, toolbar, tab bar — wherever the
    /// system placed them, including iPhone Duo's side column) must be fully
    /// inside the window and not zero-sized: a cheap catch for controls pushed
    /// offscreen or collapsed by a layout. Scrolling content is excluded — a list
    /// row partly scrolled out of view is normal.
    private func assertNothingCoveredOrOffscreen(screen: String) {
        let window = app.windows.firstMatch.frame
        let barButtons = app.navigationBars.buttons.allElementsBoundByIndex
            + app.toolbars.buttons.allElementsBoundByIndex
            + app.tabBars.buttons.allElementsBoundByIndex
        for button in barButtons where button.exists && button.isHittable {
            let frame = button.frame
            XCTAssertTrue(frame.width > 0 && frame.height > 0, "\(screen): “\(button.label)” has no size")
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame), "\(screen): “\(button.label)” \(frame) extends past the window \(window)")
        }
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        let config = env["DUO_UI_CONFIG"] ?? "run"
        attachment.name = "\(config)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = env["DUO_UI_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(config)-\(name).png")
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
