import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode {
        case login
        case register
    }

    enum Status: Equatable {
        case idle
        case loading
        case failure(String)
    }

    // Form
    @Published var account: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var rememberMe: Bool = true
    @Published var mode: Mode = .login

    // Interaction state
    @Published var accountError: String?
    @Published var passwordError: String?
    @Published var confirmPasswordError: String?
    @Published private(set) var status: Status = .idle

    // Session
    @Published private(set) var session: AuthSession?
    @Published private(set) var screenshotShowDiagnostics = false

    private let service: AuthService
    private let defaults: UserDefaults
    private let eventLog: AppEventLog

    private enum Keys {
        static let session = "auth.session"
        static let rememberedAccount = "auth.rememberedAccount"
    }

    init(service: AuthService = MockAuthService(), defaults: UserDefaults = .standard,
         eventLog: AppEventLog = .shared) {
        self.service = service
        self.defaults = defaults
        self.eventLog = eventLog
        restoreSession()
        if let saved = defaults.string(forKey: Keys.rememberedAccount) {
            account = saved
        }
        configureForScreenshotIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("UITEST_FULL_FLOW") {
            // Deterministic starting point for the recorded full-flow UI test.
            session = nil
            defaults.removeObject(forKey: Keys.session)
            eventLog.clear()
            mode = .login
            account = MockAuthService.demoAccount
            password = MockAuthService.demoPassword
        }
    }

    /// Used by the GitHub Actions screenshot job: launch with
    /// `SCREENSHOT=login|login-error|register|home` (append `-dark` for dark mode)
    /// to render a fixed state.
    private func configureForScreenshotIfNeeded() {
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("SCREENSHOT=") }) else { return }
        var modeName = String(arg.dropFirst("SCREENSHOT=".count))
        if modeName.hasSuffix("-dark") {
            modeName = String(modeName.dropLast("-dark".count))
        }
        session = nil
        defaults.removeObject(forKey: Keys.session)
        switch modeName {
        case "login":
            mode = .login
            account = MockAuthService.demoAccount
            password = MockAuthService.demoPassword
        case "login-error":
            mode = .login
            account = MockAuthService.demoAccount
            password = "111111"
            status = .failure(AuthError.invalidCredentials.errorDescription ?? "账号或密码不正确")
        case "register":
            mode = .register
            account = "new@nim.app"
            password = "Nim123456!"
            confirmPassword = "Nim123456!"
        case "home", "diagnostics", "diagnostics-flow":
            session = AuthSession(
                user: User(id: "demo", account: MockAuthService.demoAccount, nickname: "Nim Demo"),
                token: "screenshot-token",
                loginDate: Date()
            )
            screenshotShowDiagnostics = modeName == "diagnostics" || modeName == "diagnostics-flow"
        default:
            break
        }
    }

    var isLoading: Bool { status == .loading }

    var canSubmit: Bool {
        !account.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && (mode == .login || !confirmPassword.isEmpty)
            && !isLoading
    }

    var passwordStrength: Validators.PasswordStrength {
        Validators.passwordStrength(for: password)
    }

    func validate() -> Bool {
        accountError = Validators.accountError(for: account)
        passwordError = Validators.passwordError(for: password)
        if mode == .register {
            confirmPasswordError = confirmPassword == password ? nil : "两次输入的密码不一致"
        } else {
            confirmPasswordError = nil
        }
        return accountError == nil && passwordError == nil && confirmPasswordError == nil
    }

    func submit() async {
        guard !isLoading else { return } // Prevent duplicate taps while loading.
        let trimmed = account.trimmingCharacters(in: .whitespaces)
        let action = mode == .login ? "登录" : "注册"
        let flow = mode == .login ? "login" : "register"
        let attemptID = UUID().uuidString
        guard validate() else {
            // Form validation is also a real login-flow failure. Record the
            // reasons (never the password value) so diagnostics can see it.
            let reasons = [accountError, passwordError, confirmPasswordError]
                .compactMap { $0 }
                .joined(separator: "；")
            eventLog.record(
                level: .warn, event: "auth.validation_failure", category: "auth",
                message: "\(action)表单校验失败：\(reasons.isEmpty ? "输入不完整" : reasons) · 账号 \(Self.maskedAccount(trimmed))",
                attributes: ["attempt_id": attemptID, "flow": flow]
            )
            return
        }
        status = .loading
        let masked = Self.maskedAccount(trimmed)
        eventLog.record(
            level: .info, event: "auth.attempt", category: "auth",
            message: "发起\(action)请求 · 账号 \(masked)",
            attributes: ["attempt_id": attemptID, "flow": flow]
        )
        let started = Date()
        do {
            let newSession: AuthSession
            switch mode {
            case .login:
                newSession = try await service.login(account: trimmed, password: password)
            case .register:
                newSession = try await service.register(account: trimmed, password: password)
            }
            session = newSession
            status = .idle
            let durationMS = Int(Date().timeIntervalSince(started) * 1000)
            eventLog.record(
                level: .info, event: "auth.success", category: "auth",
                message: "\(action)成功 · 账号 \(masked) · 耗时 \(durationMS)ms",
                attributes: ["attempt_id": attemptID, "flow": flow, "duration_ms": String(durationMS)]
            )
            persist(session: newSession)
            if rememberMe {
                defaults.set(trimmed, forKey: Keys.rememberedAccount)
            } else {
                defaults.removeObject(forKey: Keys.rememberedAccount)
            }
        } catch let error as AuthError {
            let durationMS = Int(Date().timeIntervalSince(started) * 1000)
            let isNetwork = error == .networkUnavailable
            eventLog.record(
                level: .error,
                event: isNetwork ? "network.failure" : "auth.failure",
                category: isNetwork ? "network" : "auth",
                message: "\(action)失败：\(error.localizedDescription) · 账号 \(masked)",
                attributes: ["attempt_id": attemptID, "flow": flow,
                             "duration_ms": String(durationMS), "error_code": Self.errorCode(for: error)]
            )
            status = .failure(error.localizedDescription)
        } catch {
            let durationMS = Int(Date().timeIntervalSince(started) * 1000)
            eventLog.record(
                level: .error, event: "network.failure", category: "network",
                message: "\(action)失败：网络异常 · 账号 \(masked)",
                attributes: ["attempt_id": attemptID, "flow": flow,
                             "duration_ms": String(durationMS), "error_code": "network_unavailable",
                             "underlying_error_type": String(describing: type(of: error))]
            )
            status = .failure(AuthError.networkUnavailable.localizedDescription)
        }
    }

    func switchMode() {
        mode = mode == .login ? .register : .login
        status = .idle
        accountError = nil
        passwordError = nil
        confirmPasswordError = nil
        confirmPassword = ""
    }

    func logout() {
        if let account = session?.user.account {
            eventLog.record(level: .info, event: "auth.logout", category: "auth",
                            message: "退出登录 · 账号 \(Self.maskedAccount(account))")
        }
        session = nil
        password = ""
        confirmPassword = ""
        status = .idle
        defaults.removeObject(forKey: Keys.session)
    }

    private static func maskedAccount(_ account: String) -> String {
        if let at = account.firstIndex(of: "@") {
            let name = account[..<at]
            let domain = account[account.index(after: at)...]
            return "\(name.first.map(String.init) ?? "*")***@\(domain)"
        }
        guard account.count > 4 else { return "****" }
        return "\(account.prefix(2))****\(account.suffix(2))"
    }

    private static func errorCode(for error: AuthError) -> String {
        switch error {
        case .invalidCredentials: return "invalid_credentials"
        case .accountNotFound: return "account_not_found"
        case .networkUnavailable: return "network_unavailable"
        }
    }

    private func persist(session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Keys.session)
        }
    }

    private func restoreSession() {
        guard let data = defaults.data(forKey: Keys.session),
              let saved = try? JSONDecoder().decode(AuthSession.self, from: data) else { return }
        session = saved
    }
}
