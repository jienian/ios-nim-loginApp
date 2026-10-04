import Foundation

enum Validators {
    static func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Mainland China mobile number: 11 digits starting with 1.
    static func isValidPhone(_ value: String) -> Bool {
        let pattern = #"^1[3-9]\d{9}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    static func isValidAccount(_ value: String) -> Bool {
        isValidEmail(value) || isValidPhone(value)
    }

    static func accountError(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "请输入邮箱或手机号" }
        if !isValidAccount(trimmed) { return "邮箱或手机号格式不正确" }
        return nil
    }

    static func passwordError(for value: String) -> String? {
        if value.isEmpty { return "请输入密码" }
        if value.count < 6 { return "密码至少 6 位" }
        return nil
    }

    enum PasswordStrength: String {
        case weak = "弱"
        case medium = "中"
        case strong = "强"
    }

    static func passwordStrength(for value: String) -> PasswordStrength {
        var score = 0
        if value.count >= 6 { score += 1 }
        if value.count >= 10 { score += 1 }
        if value.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if value.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if value.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { score += 1 }
        switch score {
        case 0...2: return .weak
        case 3: return .medium
        default: return .strong
        }
    }
}
