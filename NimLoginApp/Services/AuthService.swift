import Foundation

enum AuthError: LocalizedError, Equatable {
    case invalidCredentials
    case accountNotFound
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "账号或密码不正确"
        case .accountNotFound: return "账号不存在，请先注册"
        case .networkUnavailable: return "网络异常，请稍后重试"
        }
    }
}

protocol AuthService {
    func login(account: String, password: String) async throws -> AuthSession
    func register(account: String, password: String) async throws -> AuthSession
}

/// Demo implementation. Replace this with a real API client conforming to
/// `AuthService` and the view model / views stay unchanged.
struct MockAuthService: AuthService {
    var delayNanoseconds: UInt64 = 1_200_000_000

    static let demoAccount = "demo@nim.app"
    static let demoPassword = "123456"

    func login(account: String, password: String) async throws -> AuthSession {
        try await Task.sleep(nanoseconds: delayNanoseconds)

        // The demo account enforces its password, so the failure path is testable.
        if account == Self.demoAccount, password != Self.demoPassword {
            throw AuthError.invalidCredentials
        }

        // Any other well-formed account succeeds in demo mode.
        return Self.makeSession(account: account)
    }

    func register(account: String, password: String) async throws -> AuthSession {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return Self.makeSession(account: account)
    }

    private static func makeSession(account: String) -> AuthSession {
        let nickname = account == demoAccount ? "Nim Demo" : "Nim User"
        return AuthSession(
            user: User(id: UUID().uuidString, account: account, nickname: nickname),
            token: "mock-token-\(UUID().uuidString)",
            loginDate: Date()
        )
    }
}
