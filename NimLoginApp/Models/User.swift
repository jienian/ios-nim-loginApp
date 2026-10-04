import Foundation

struct User: Codable, Equatable, Identifiable {
    let id: String
    let account: String
    let nickname: String
}

struct AuthSession: Codable, Equatable {
    let user: User
    let token: String
    let loginDate: Date
}
