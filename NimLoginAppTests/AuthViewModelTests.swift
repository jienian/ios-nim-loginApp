import XCTest
@testable import NimLoginApp

@MainActor
final class AuthViewModelTests: XCTestCase {
    private func makeViewModel() -> AuthViewModel {
        let defaults = UserDefaults(suiteName: "AuthViewModelTests-\(UUID().uuidString)")!
        return AuthViewModel(service: MockAuthService(delayNanoseconds: 1_000), defaults: defaults)
    }

    func testLoginSuccess() async {
        let vm = makeViewModel()
        vm.account = "demo@nim.app"
        vm.password = "123456"
        await vm.submit()
        XCTAssertNotNil(vm.session)
        XCTAssertEqual(vm.session?.user.account, "demo@nim.app")
    }

    func testLoginWrongPassword() async {
        let vm = makeViewModel()
        vm.account = "demo@nim.app"
        vm.password = "wrong-password"
        await vm.submit()
        XCTAssertNil(vm.session)
        if case .failure = vm.status {} else {
            XCTFail("Expected failure status")
        }
    }

    func testInvalidInputDoesNotSubmit() async {
        let vm = makeViewModel()
        vm.account = "not-an-email"
        vm.password = "123"
        await vm.submit()
        XCTAssertNil(vm.session)
        XCTAssertNotNil(vm.accountError)
        XCTAssertNotNil(vm.passwordError)
    }

    func testRegisterConfirmMismatch() async {
        let vm = makeViewModel()
        vm.switchMode()
        vm.account = "new@nim.app"
        vm.password = "123456"
        vm.confirmPassword = "654321"
        await vm.submit()
        XCTAssertNil(vm.session)
        XCTAssertNotNil(vm.confirmPasswordError)
    }
}
