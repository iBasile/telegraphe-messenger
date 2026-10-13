import Foundation

public struct AuthTokens: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let deviceID: String
    public init(accessToken: String, refreshToken: String, deviceID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.deviceID = deviceID
    }
}

public struct AuthUser: Sendable, Equatable {
    public let id: String
    public let email: String
    public init(id: String, email: String) {
        self.id = id
        self.email = email
    }
}

public enum AuthError: Error, Equatable {
    case invalidEmail
    case passwordTooShort
    case passwordsDoNotMatch
    case emailAlreadyUsed
    case invalidCredentials
    case emailVerificationRequired
    case invalidVerificationToken
    case invalidResetToken
    case tooManyAttempts
    case networkUnavailable
    case server(message: String)
    case notAuthenticated
    case storageFailure
}

public protocol AuthenticationClient: Sendable {
    func register(email: String, password: String, displayName: String, deviceID: String) async throws
    func verifyEmail(token: String) async throws
    func login(email: String, password: String, deviceID: String) async throws -> (AuthTokens, AuthUser)
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokens
    func logout(refreshToken: String, deviceID: String) async throws
    func requestPasswordReset(email: String) async throws
    func confirmPasswordReset(token: String, password: String) async throws
}

public struct ServerAuthenticationClient: AuthenticationClient {
    public let http: any HTTPClient
    public init(http: any HTTPClient) {
        self.http = http
    }

    public func register(email: String, password: String, displayName: String, deviceID: String) async throws {
        let response = try await request(
            method: "POST",
            path: "/auth/register",
            body: ["email": email, "password": password, "displayName": displayName, "deviceId": deviceID]
        )
        try ensure(response, accepted: [201])
    }

    public func verifyEmail(token: String) async throws {
        let response = try await request(method: "POST", path: "/auth/verify-email", body: ["token": token])
        try ensure(response, accepted: [200])
    }

    public func login(email: String, password: String, deviceID: String) async throws -> (AuthTokens, AuthUser) {
        let response = try await request(
            method: "POST",
            path: "/auth/login",
            body: ["email": email, "password": password, "deviceId": deviceID]
        )
        try ensure(response, accepted: [200])
        let value = try JSONDecoder().decode(LoginResponse.self, from: response.data)
        return (
            AuthTokens(accessToken: value.accessToken, refreshToken: value.refreshToken, deviceID: deviceID),
            AuthUser(id: value.user.id, email: value.user.email)
        )
    }

    public func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokens {
        let response = try await request(
            method: "POST",
            path: "/auth/refresh",
            body: ["token": refreshToken, "deviceId": deviceID]
        )
        try ensure(response, accepted: [200])
        let value = try JSONDecoder().decode(TokenResponse.self, from: response.data)
        return AuthTokens(accessToken: value.accessToken, refreshToken: value.refreshToken, deviceID: deviceID)
    }

    public func logout(refreshToken: String, deviceID: String) async throws {
        let response = try await request(
            method: "POST",
            path: "/auth/logout",
            body: ["token": refreshToken, "deviceId": deviceID]
        )
        try ensure(response, accepted: [204])
    }

    public func requestPasswordReset(email: String) async throws {
        let response = try await request(method: "POST", path: "/auth/password-reset/request", body: ["email": email])
        try ensure(response, accepted: [200])
    }

    public func confirmPasswordReset(token: String, password: String) async throws {
        let response = try await request(
            method: "POST",
            path: "/auth/password-reset/confirm",
            body: ["token": token, "password": password]
        )
        try ensure(response, accepted: [200])
    }

    func request(method: String, path: String, body: [String: String]) async throws -> HTTPResponse {
        let data = try JSONSerialization.data(withJSONObject: body)
        do {
            return try await http.send(method: method, path: path, body: data, headers: [:])
        } catch HTTPClientError.networkUnavailable {
            throw AuthError.networkUnavailable
        }
    }

    func ensure(_ response: HTTPResponse, accepted: [Int]) throws {
        guard !accepted.contains(response.statusCode) else { return }
        let message = (try? JSONDecoder().decode(ServerError.self, from: response.data).error) ?? ""
        switch response.statusCode {
        case 401: throw AuthError.invalidCredentials
        case 403 where message == "Adresse e-mail non vérifiée": throw AuthError.emailVerificationRequired
        case 409: throw AuthError.emailAlreadyUsed
        case 429: throw AuthError.tooManyAttempts
        case 400 where message.contains("Jeton"): throw AuthError.invalidVerificationToken
        default: throw AuthError.server(message: message.isEmpty ? "Le serveur a refusé la demande." : message)
        }
    }
}

public actor AuthService {
    public let client: any AuthenticationClient
    public let storage: any SecureStorage
    public private(set) var tokens: AuthTokens?
    public private(set) var user: AuthUser?
    let deviceStorageKey = "telegraphe.device_id"
    let accessStorageKey = "telegraphe.access_token"
    let refreshStorageKey = "telegraphe.refresh_token"

    public init(client: any AuthenticationClient, storage: any SecureStorage) {
        self.client = client
        self.storage = storage
    }

    public func register(email: String, password: String, confirmation: String, displayName: String) async throws {
        try validate(email: email, password: password, confirmation: confirmation, displayName: displayName)
        try await client.register(email: email.lowercased(), password: password, displayName: displayName, deviceID: deviceID())
    }

    public func verifyEmail(token: String) async throws {
        try await client.verifyEmail(token: token)
    }

    public func login(email: String, password: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        guard password.count >= 12 else { throw AuthError.passwordTooShort }
        let result = try await client.login(email: email.lowercased(), password: password, deviceID: deviceID())
        try save(result.0)
        tokens = result.0
        user = result.1
    }

    public func restoreSession() async throws -> Bool {
        guard let refresh = storage.string(forKey: refreshStorageKey) else { return false }
        let device = deviceID()
        do {
            let refreshed = try await client.refresh(refresh, deviceID: device)
            try save(refreshed)
            tokens = refreshed
            return true
        } catch {
            try clear()
            return false
        }
    }

    public func refresh() async throws {
        guard let refresh = storage.string(forKey: refreshStorageKey) else { throw AuthError.notAuthenticated }
        let refreshed = try await client.refresh(refresh, deviceID: deviceID())
        try save(refreshed)
        tokens = refreshed
    }

    public func logout() async throws {
        if let refresh = storage.string(forKey: refreshStorageKey) {
            try await client.logout(refreshToken: refresh, deviceID: deviceID())
        }
        try clear()
        tokens = nil
        user = nil
    }

    public func requestPasswordReset(email: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        try await client.requestPasswordReset(email: email.lowercased())
    }

    public func confirmPasswordReset(token: String, password: String, confirmation: String) async throws {
        try validate(email: "reset@example.com", password: password, confirmation: confirmation, displayName: "reset")
        try await client.confirmPasswordReset(token: token, password: password)
    }

    public func accessToken() -> String? {
        tokens?.accessToken ?? storage.string(forKey: accessStorageKey)
    }

    func deviceID() -> String {
        if let existing = storage.string(forKey: deviceStorageKey) { return existing }
        let value = UUID().uuidString.lowercased()
        try? storage.set(value, forKey: deviceStorageKey)
        return value
    }

    func save(_ value: AuthTokens) throws {
        do {
            try storage.set(value.accessToken, forKey: accessStorageKey)
            try storage.set(value.refreshToken, forKey: refreshStorageKey)
        } catch {
            throw AuthError.storageFailure
        }
    }

    func clear() throws {
        do {
            try storage.removeValue(forKey: accessStorageKey)
            try storage.removeValue(forKey: refreshStorageKey)
        } catch {
            throw AuthError.storageFailure
        }
    }

    func validate(email: String, password: String, confirmation: String, displayName: String) throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        guard password.count >= 12 else { throw AuthError.passwordTooShort }
        guard password == confirmation else { throw AuthError.passwordsDoNotMatch }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthError.server(message: "Le nom d’affichage est obligatoire.")
        }
    }

    func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".") && !email.contains(" ")
    }
}

struct LoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUserResponse
}
struct AuthUserResponse: Decodable {
    let id: String
    let email: String
}
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
}
struct ServerError: Decodable {
    let error: String
}
