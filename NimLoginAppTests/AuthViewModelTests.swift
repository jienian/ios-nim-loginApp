import XCTest
@testable import NimLoginApp

@MainActor
final class AuthViewModelTests: XCTestCase {
    private func makeViewModel(eventLog: AppEventLog? = nil) -> AuthViewModel {
        let defaults = UserDefaults(suiteName: "AuthViewModelTests-\(UUID().uuidString)")!
        return AuthViewModel(service: MockAuthService(delayNanoseconds: 1_000), defaults: defaults,
                             eventLog: eventLog ?? AppEventLog(defaults: defaults))
    }

    private struct NetworkFailingService: AuthService {
        func login(account: String, password: String) async throws -> AuthSession {
            throw AuthError.networkUnavailable
        }

        func register(account: String, password: String) async throws -> AuthSession {
            throw AuthError.networkUnavailable
        }
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

    func testLoginFailureWritesStructuredEventWithoutPassword() async {
        let defaults = UserDefaults(suiteName: "AuthViewModelEventTests-\(UUID().uuidString)")!
        let eventLog = AppEventLog(defaults: defaults)
        let vm = AuthViewModel(service: MockAuthService(delayNanoseconds: 1_000), defaults: defaults, eventLog: eventLog)
        vm.account = "demo@nim.app"
        vm.password = "wrong-password"
        await vm.submit()

        let failure = eventLog.entries().first { $0.event == "auth.failure" }
        XCTAssertNotNil(failure)
        XCTAssertEqual(failure?.attributes?["error_code"], "invalid_credentials")
        XCTAssertNotNil(failure?.attributes?["attempt_id"])
        XCTAssertFalse(eventLog.entries().contains { $0.message.contains("wrong-password") })
    }

    func testNetworkAuthErrorWritesNetworkEvent() async {
        let defaults = UserDefaults(suiteName: "AuthViewModelNetworkTests-\(UUID().uuidString)")!
        let eventLog = AppEventLog(defaults: defaults)
        let vm = AuthViewModel(service: NetworkFailingService(), defaults: defaults, eventLog: eventLog)
        vm.account = "demo@nim.app"
        vm.password = "123456"
        await vm.submit()

        let failure = eventLog.entries().first { $0.event == "network.failure" }
        XCTAssertNotNil(failure)
        XCTAssertEqual(failure?.category, "network")
        XCTAssertEqual(failure?.attributes?["error_code"], "network_unavailable")
    }

    func testInvalidInputWritesValidationEventWithoutPassword() async {
        let defaults = UserDefaults(suiteName: "AuthViewModelValidationTests-\(UUID().uuidString)")!
        let eventLog = AppEventLog(defaults: defaults)
        let vm = AuthViewModel(service: MockAuthService(delayNanoseconds: 1_000), defaults: defaults, eventLog: eventLog)
        vm.account = "not-an-email"
        vm.password = "123"
        await vm.submit()

        XCTAssertNil(vm.session)
        let event = eventLog.entries().first { $0.event == "auth.validation_failure" }
        XCTAssertNotNil(event)
        XCTAssertFalse(eventLog.entries().contains { $0.message.contains("123") && $0.message.contains("密码") == false })
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
