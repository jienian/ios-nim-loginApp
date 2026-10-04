import XCTest
@testable import NimLoginApp

final class ValidatorsTests: XCTestCase {
    func testEmail() {
        XCTAssertTrue(Validators.isValidEmail("demo@nim.app"))
        XCTAssertFalse(Validators.isValidEmail("demo@"))
        XCTAssertFalse(Validators.isValidEmail("demo"))
    }

    func testPhone() {
        XCTAssertTrue(Validators.isValidPhone("13800138000"))
        XCTAssertFalse(Validators.isValidPhone("12345"))
        XCTAssertFalse(Validators.isValidPhone("23800138000"))
    }

    func testPasswordError() {
        XCTAssertNotNil(Validators.passwordError(for: ""))
        XCTAssertNotNil(Validators.passwordError(for: "123"))
        XCTAssertNil(Validators.passwordError(for: "123456"))
    }

    func testStrength() {
        XCTAssertEqual(Validators.passwordStrength(for: "123456"), .weak)
        XCTAssertEqual(Validators.passwordStrength(for: "Abc123456!"), .strong)
    }
}
