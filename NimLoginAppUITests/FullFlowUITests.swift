import XCTest

/// Full user journey used for the recorded demo video:
/// launch -> login -> home -> diagnostics centre -> collect logs -> fault analysis -> result.
final class FullFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFullAppFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FULL_FLOW"]
        app.launch()

        // Login screen appears and holds briefly so it reads on video.
        let loginTitle = app.staticTexts["欢迎回来"]
        XCTAssertTrue(loginTitle.waitForExistence(timeout: 10))
        sleep(2)

        // Account field (prefilled by the UITEST flag; still tap + type to show interaction).
        let accountField = app.textFields.firstMatch
        XCTAssertTrue(accountField.waitForExistence(timeout: 5))
        accountField.tap()
        // Ensure the demo account is present even if prefill changes.
        if (accountField.value as? String)?.contains("demo@nim.app") != true {
            accountField.typeText("demo@nim.app")
        }
        sleep(1)

        // Password field
        let passwordField = app.secureTextFields.firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        if (passwordField.value as? String)?.isEmpty != false {
            passwordField.typeText("123456")
        }
        sleep(1)

        // Tap login
        let loginButton = app.buttons["登录"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
        loginButton.tap()

        // Home
        let homeText = app.staticTexts["登录成功"]
        XCTAssertTrue(homeText.waitForExistence(timeout: 10))
        sleep(3)

        // Enter diagnostics centre
        let diagButton = app.buttons["工程师诊断中心"]
        XCTAssertTrue(diagButton.waitForExistence(timeout: 5))
        diagButton.tap()

        let diagTitle = app.staticTexts["硬件缺陷追踪（3）"]
        XCTAssertTrue(diagTitle.waitForExistence(timeout: 10))
        sleep(3)

        // Collect logs
        let collectButton = app.buttons["一键收集诊断日志"]
        // It may be below the fold; scroll until hittable.
        var attempts = 0
        while !collectButton.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(collectButton.waitForExistence(timeout: 5))
        collectButton.tap()

        // Wait for collection to finish (export button appears)
        let exportButton = app.buttons["导出日志包"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 25))
        sleep(2)

        // Run fault analysis
        let analyseButton = app.buttons["开始故障分析"]
        attempts = 0
        while !analyseButton.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        analyseButton.tap()

        // Result: root-cause summary. Scroll it fully into view and hold it.
        let result = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "最可能根因")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25))
        var scrolls = 0
        while !result.isHittable && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        sleep(2)
        // One gentle extra scroll so the confidence/evidence card below is in frame too.
        if result.isHittable {
            app.swipeUp()
        }
        sleep(5) // hold the conclusion on screen for the end of the video
    }
}
