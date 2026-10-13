import Testing
import Foundation
@testable import TelegrapheCore

final class InMemorySecureStorage: SecureStorage, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) throws { values[key] = value }
    func removeValue(forKey key: String) throws { values[key] = nil }
}

final class FakeAuthenticationClient: AuthenticationClient, @unchecked Sendable {
    var registered = false
    var verified = false
    var loginCount = 0
    var refreshCount = 0
    var loggedOut = false
    var shouldRejectEmail = false
    var shouldRejectPassword = false
    var accessToken = "access-1"
    var refreshToken = "refresh-1"

    func register(email: String, password: String, displayName: String, deviceID: String) async throws {
        if shouldRejectEmail { throw AuthError.emailAlreadyUsed }
        registered = true
    }
    func verifyEmail(token: String) async throws { verified = true }
    func login(email: String, password: String, deviceID: String) async throws -> (AuthTokens, AuthUser) {
        loginCount += 1
        if shouldRejectPassword { throw AuthError.invalidCredentials }
        guard verified else { throw AuthError.emailVerificationRequired }
        return (
            AuthTokens(accessToken: accessToken, refreshToken: refreshToken, deviceID: deviceID),
            AuthUser(id: "user", email: email)
        )
    }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokens {
        refreshCount += 1
        self.refreshToken = "refresh-\(refreshCount + 1)"
        return AuthTokens(accessToken: "access-\(refreshCount + 1)", refreshToken: self.refreshToken, deviceID: deviceID)
    }
    func logout(refreshToken: String, deviceID: String) async throws { loggedOut = true }
    func requestPasswordReset(email: String) async throws {}
    func confirmPasswordReset(token: String, password: String) async throws {}
}

@Test
func registrationSucceeds() async throws {
    let client = FakeAuthenticationClient()
    let service = AuthService(client: client, storage: InMemorySecureStorage())
    try await service.register(
        email: "person@example.com",
        password: "correct horse battery staple",
        confirmation: "correct horse battery staple",
        displayName: "Person"
    )
    #expect(client.registered)
}

@Test
func registrationRejectsUsedEmail() async {
    let client = FakeAuthenticationClient()
    client.shouldRejectEmail = true
    let service = AuthService(client: client, storage: InMemorySecureStorage())
    do {
        try await service.register(email: "person@example.com", password: "correct horse battery staple", confirmation: "correct horse battery staple", displayName: "Person")
        Issue.record("L’inscription aurait dû échouer")
    } catch {
        #expect((error as? AuthError) == .emailAlreadyUsed)
    }
}

@Test
func loginRejectsWrongPassword() async {
    let client = FakeAuthenticationClient()
    client.verified = true
    client.shouldRejectPassword = true
    let service = AuthService(client: client, storage: InMemorySecureStorage())
    do {
        try await service.login(email: "person@example.com", password: "wrong password")
        Issue.record("La connexion aurait dû échouer")
    } catch {
        #expect((error as? AuthError) == .invalidCredentials)
    }
}

@Test
func expiredSessionRefreshesAndStoresRotatedTokens() async throws {
    let client = FakeAuthenticationClient()
    let storage = InMemorySecureStorage()
    let service = AuthService(client: client, storage: storage)
    try storage.set("old-refresh", forKey: "telegraphe.refresh_token")
    #expect(try await service.restoreSession())
    #expect(client.refreshCount == 1)
    #expect(storage.string(forKey: "telegraphe.refresh_token") == "refresh-2")
}

@Test
func logoutRevokesAndClearsSession() async throws {
    let client = FakeAuthenticationClient()
    client.verified = true
    let storage = InMemorySecureStorage()
    let service = AuthService(client: client, storage: storage)
    try await service.login(email: "person@example.com", password: "correct horse battery staple")
    try await service.logout()
    #expect(client.loggedOut)
    #expect(storage.string(forKey: "telegraphe.refresh_token") == nil)
}
