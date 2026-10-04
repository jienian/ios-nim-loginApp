import XCTest

/// Full user journey used for the recorded demo video:
/// launch -> wrong password (login fails) -> correct password (login succeeds)
/// -> home -> diagnostics centre -> collect logs -> fault analysis -> result
/// -> back home -> log out -> login screen again.
final class FullFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Clear a text/secure field by deleting its current (masked) contents.
    private func clearField(_ field: XCUIElement) {
        field.tap()
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
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

        // --- Attempt 1: wrong password -> login must FAIL with an error ---
        clearField(passwordField)
        passwordField.typeText("111111")
        sleep(1)

        let loginButton = app.buttons["登录"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
        loginButton.tap()

        let errorText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "账号或密码不正确")).firstMatch
        XCTAssertTrue(errorText.waitForExistence(timeout: 10))
        sleep(3) // hold the failure message on screen

        // --- Attempt 2: correct password -> login succeeds ---
        clearField(passwordField)
        passwordField.typeText("123456")
        sleep(1)
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

        // Wait for collection to finish (export button appears).
        // The export row sits below the collected log entries, and a SwiftUI
        // List only materialises rows near the viewport — so scroll while
        // waiting instead of expecting it to exist off-screen.
        let exportButton = app.buttons["导出日志包"]
        var exportAttempts = 0
        while !exportButton.exists && exportAttempts < 10 {
            if exportButton.waitForExistence(timeout: 3) { break }
            app.swipeUp()
            exportAttempts += 1
        }
        XCTAssertTrue(exportButton.exists, "导出日志包 should appear after log collection finishes")
        sleep(2)

        // Run fault analysis
        let analyseButton = app.buttons["开始故障分析"]
        attempts = 0
        while !analyseButton.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        analyseButton.tap()

        // Result: the real wrong-password event is captured as an auth hypothesis.
        let result = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "登录 / 认证异常")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25))
        sleep(2)
        for _ in 0..<3 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.1, thenDragTo: end)
            sleep(1)
        }
        sleep(5) // hold the conclusion on screen

        // --- Close the loop: back home, log out, land on the login screen ---
        let backButton = app.buttons["主页"]
        if backButton.exists {
            backButton.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }
        let logoutButton = app.buttons["退出登录"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 10))
        sleep(2)
        logoutButton.tap()
        XCTAssertTrue(app.staticTexts["欢迎回来"].waitForExistence(timeout: 10))
        sleep(3) // end where we started: the login screen
    }
}
