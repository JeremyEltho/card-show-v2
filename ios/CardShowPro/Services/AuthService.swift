import Foundation

struct AuthUser: Codable {
    let id: String
    let email: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
    }
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct RefreshResponse: Codable {
    let accessToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

enum AuthError: Error {
    case notAuthenticated
    case tokenExpired
    case networkError(String)
}

actor AuthService {
    static let shared = AuthService()
    private let keychain = KeychainHelper.shared

    private(set) var currentUser: AuthUser?

    func login(email: String, password: String, network: NetworkService) async throws -> AuthUser {
        let body = ["email": email, "password": password]
        let response: AuthResponse = try await network.post("/auth/login", body: body, authenticated: false)
        storeTokens(response)
        currentUser = response.user
        return response.user
    }

    func register(email: String, password: String, displayName: String, network: NetworkService) async throws -> AuthUser {
        let body = ["email": email, "password": password, "display_name": displayName]
        let response: AuthResponse = try await network.post("/auth/register", body: body, authenticated: false)
        storeTokens(response)
        currentUser = response.user
        return response.user
    }

    func logout(network: NetworkService) async {
        if let refresh = keychain.get("refresh_token") {
            let body = ["refresh_token": refresh]
            _ = try? await network.post("/auth/logout", body: body, authenticated: false) as EmptyResponse
        }
        clearTokens()
        currentUser = nil
    }

    func accessToken() throws -> String {
        guard let token = keychain.get("access_token") else { throw AuthError.notAuthenticated }
        return token
    }

    func refreshIfNeeded(network: NetworkService) async throws -> String {
        guard let refreshToken = keychain.get("refresh_token") else { throw AuthError.notAuthenticated }
        let body = ["refresh_token": refreshToken]
        let response: RefreshResponse = try await network.post("/auth/refresh", body: body, authenticated: false)
        keychain.set(response.accessToken, key: "access_token")
        return response.accessToken
    }

    func isAuthenticated() -> Bool {
        keychain.get("access_token") != nil
    }

    private func storeTokens(_ response: AuthResponse) {
        keychain.set(response.accessToken, key: "access_token")
        keychain.set(response.refreshToken, key: "refresh_token")
    }

    private func clearTokens() {
        keychain.delete("access_token")
        keychain.delete("refresh_token")
    }
}

private struct EmptyResponse: Codable {}
