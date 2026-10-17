import Foundation

public struct MailboxItem: Sendable, Equatable {
    public let id: Int64
    public let clientID: String
    public let envelope: Data
    public init(id: Int64, clientID: String, envelope: Data) {
        self.id = id
        self.clientID = clientID
        self.envelope = envelope
    }
}

public protocol MailboxHTTPClient: Sendable {
    func pending(cursor: Int64, accessToken: String) async throws -> (cursor: Int64, items: [MailboxItem])
    func acknowledge(clientID: String, accessToken: String) async throws
}

public struct ServerMailboxHTTPClient: MailboxHTTPClient {
    public let http: any HTTPClient
    public let tokenProvider: (any AccessTokenProvider)?
    public init(http: any HTTPClient) {
        self.http = http
        self.tokenProvider = nil
    }

    public init(http: any HTTPClient, tokenProvider: any AccessTokenProvider) {
        self.http = http
        self.tokenProvider = tokenProvider
    }

    public func pending(cursor: Int64, accessToken: String) async throws -> (cursor: Int64, items: [MailboxItem]) {
        let response = try await http.send(
            method: "GET",
            path: "/mailbox?cursor=\(cursor)",
            body: nil,
            headers: ["Authorization": "Bearer \(accessToken)"]
        )
        guard response.statusCode == 200 else { throw MessagingAPIError.requestFailed(response.statusCode) }
        let value = try JSONDecoder().decode(MailboxResponse.self, from: response.data)
        return (
            value.cursor,
            try value.items.map {
                guard let data = Data(base64Encoded: $0.envelope) else { throw MessagingAPIError.invalidEnvelope }
                return MailboxItem(id: $0.id, clientID: $0.clientId, envelope: data)
            }
        )
    }

    public func acknowledge(clientID: String, accessToken: String) async throws {
        let response = try await http.send(
            method: "POST",
            path: "/mailbox/\(clientID)/ack",
            body: nil,
            headers: ["Authorization": "Bearer \(accessToken)"]
        )
        guard response.statusCode == 204 else { throw MessagingAPIError.requestFailed(response.statusCode) }
    }

    public func pending(cursor: Int64) async throws -> (cursor: Int64, items: [MailboxItem]) {
        guard let tokenProvider else { throw AuthError.notAuthenticated }
        do {
            return try await pending(cursor: cursor, accessToken: tokenProvider.accessToken())
        } catch MessagingAPIError.requestFailed(401) {
            return try await pending(cursor: cursor, accessToken: tokenProvider.refreshAccessToken())
        }
    }

    public func acknowledge(clientID: String) async throws {
        guard let tokenProvider else { throw AuthError.notAuthenticated }
        do {
            try await acknowledge(clientID: clientID, accessToken: tokenProvider.accessToken())
        } catch MessagingAPIError.requestFailed(401) {
            try await acknowledge(clientID: clientID, accessToken: tokenProvider.refreshAccessToken())
        }
    }
}

public enum MessagingAPIError: Error, Equatable {
    case requestFailed(Int)
    case invalidEnvelope
}

private struct MailboxResponse: Decodable {
    let cursor: Int64
    let items: [MailboxResponseItem]
}

private struct MailboxResponseItem: Decodable {
    let id: Int64
    let clientId: String
    let envelope: String
}
