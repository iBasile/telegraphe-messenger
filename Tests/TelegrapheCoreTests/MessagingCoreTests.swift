import Foundation
import Testing
import TelegrapheCore

private enum FakeError: Error {
    case disconnected
    case noMessage
}

private actor FakeTransport: MessageTransport {
    var connectAttempts = 0
    var failFirstConnection = false
    var sent: [ProtocolEnvelope] = []

    func connect(accessToken: String, deviceID: String) async throws {
        connectAttempts += 1
        if failFirstConnection && connectAttempts == 1 {
            throw TransportError.authenticationRequired
        }
    }

    func send(_ envelope: ProtocolEnvelope) async throws {
        sent.append(envelope)
    }

    func receive() async throws -> ProtocolEnvelope {
        throw FakeError.noMessage
    }

    func close() async {}

    func sentEnvelopes() -> [ProtocolEnvelope] { sent }
}

private actor FakeMailbox: MailboxHTTPClient {
    var items: [MailboxItem]
    var acknowledgements: [String] = []

    init(items: [MailboxItem] = []) {
        self.items = items
    }

    func pending(cursor: Int64, accessToken: String) async throws -> (cursor: Int64, items: [MailboxItem]) {
        (items.last?.id ?? cursor, items.filter { $0.id > cursor })
    }

    func acknowledge(clientID: String, accessToken: String) async throws {
        acknowledgements.append(clientID)
    }

    func acknowledgedIDs() -> [String] { acknowledgements }
}

private actor FakeTokenProvider: AccessTokenProvider {
    var refreshCount = 0
    let initial: String
    let refreshed: String

    init(initial: String = "expired", refreshed: String = "fresh") {
        self.initial = initial
        self.refreshed = refreshed
    }

    func accessToken() async throws -> String { initial }

    func refreshAccessToken() async throws -> String {
        refreshCount += 1
        return refreshed
    }

    func refreshes() -> Int { refreshCount }
}

private actor FakeHTTPClient: HTTPClient {
    var responses: [HTTPResponse]
    var authorizationHeaders: [String] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(method: String, path: String, body: Data?, headers: [String: String]) async throws -> HTTPResponse {
        authorizationHeaders.append(headers["Authorization"] ?? "")
        return responses.removeFirst()
    }

    func headers() -> [String] { authorizationHeaders }
}

@Test
func outboxSendsMessageAndServerAckMarksItSent() async throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "conversation", otherUserID: "other", title: "Other", lastMessage: nil))
    _ = try database.enqueueMessage(conversationID: "conversation", senderUserID: "me", text: "Bonjour", id: "message")
    let transport = FakeTransport()
    await OutboxWorker(database: database, transport: transport, deviceID: "device").sendPending()

    let sent = try #require(await transport.sentEnvelopes().first)
    #expect(sent.clientID == "message")
    var ack = Telegraphe_V1_ServerAck()
    ack.messageClientID = "message"
    ack.accepted = true
    let synchronizer = MessagingSynchronizer(database: database, transport: transport, mailbox: FakeMailbox())
    try await synchronizer.processIncoming(
        ProtocolEnvelope(type: 4, clientID: "message", timestamp: 1, conversationID: "conversation", senderDeviceID: "server", payload: try ack.serializedData()),
        deviceID: "device"
    )
    #expect(try database.messages(in: "conversation").first?.status == .sent)
}

@Test
func outboxResendsSameClientIDAfterDisconnectWithoutCreatingAnotherMessage() async throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "conversation", otherUserID: "other", title: "Other", lastMessage: nil))
    _ = try database.enqueueMessage(conversationID: "conversation", senderUserID: "me", text: "Bonjour", id: "message")
    let transport = FakeTransport()
    let worker = OutboxWorker(database: database, transport: transport, deviceID: "device")
    await worker.sendPending()
    await worker.sendPending()
    #expect(await transport.sentEnvelopes().map(\.clientID) == ["message", "message"])
    #expect(try database.messages(in: "conversation").count == 1)
}

@Test
func recoveryProcessesAndAcknowledgesMailboxInAscendingOrder() async throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "conversation", otherUserID: "sender", title: "Sender", lastMessage: nil))
    let codec = ProtobufProtocolCodec()
    let envelopes = [1, 2].map { number in
        ProtocolEnvelope(type: 3, clientID: "message-\(number)", timestamp: Int64(number), conversationID: "conversation", senderDeviceID: "sender-device", payload: textPayload("message-\(number)"))
    }
    let mailbox = FakeMailbox(items: [
        MailboxItem(id: 2, clientID: "message-2", envelope: try! codec.encode(envelopes[1])),
        MailboxItem(id: 1, clientID: "message-1", envelope: try! codec.encode(envelopes[0])),
    ])
    let transport = FakeTransport()
    let synchronizer = MessagingSynchronizer(database: database, transport: transport, mailbox: mailbox)
    do {
        try await synchronizer.synchronize(accessToken: "token", deviceID: "device")
        Issue.record("The fake transport should stop synchronization")
    } catch FakeError.noMessage {
    }
    #expect(await mailbox.acknowledgedIDs() == ["message-1", "message-2"])
    #expect(try database.cursor(deviceID: "device") == 2)
    #expect(try database.messages(in: "conversation").map(\.id) == ["message-1", "message-2"])
}

@Test
func realtimeThenRecoveryIsIdempotent() async throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "conversation", otherUserID: "sender", title: "Sender", lastMessage: nil))
    let envelope = ProtocolEnvelope(type: 3, clientID: "message", timestamp: 1, conversationID: "conversation", senderDeviceID: "sender-device", payload: textPayload("Bonjour"))
    let transport = FakeTransport()
    let synchronizer = MessagingSynchronizer(database: database, transport: transport, mailbox: FakeMailbox())
    try await synchronizer.processIncoming(envelope, deviceID: "device")
    try await synchronizer.processIncoming(envelope, deviceID: "device")
    #expect(try database.messages(in: "conversation").count == 1)
}

@Test
func messageStatusesProgressFromSentToDeliveredToRead() async throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "conversation", otherUserID: "other", title: "Other", lastMessage: nil))
    _ = try database.enqueueMessage(conversationID: "conversation", senderUserID: "me", text: "Bonjour", id: "message")
    let transport = FakeTransport()
    let synchronizer = MessagingSynchronizer(database: database, transport: transport, mailbox: FakeMailbox())
    for (type, status) in [(UInt8(4), MessageStatus.sent), (UInt8(5), MessageStatus.delivered), (UInt8(6), MessageStatus.read)] {
        var payload: Data
        if type == 4 {
            var ack = Telegraphe_V1_ServerAck()
            ack.messageClientID = "message"
            ack.accepted = true
            payload = try ack.serializedData()
        } else {
            var receipt = Telegraphe_V1_Receipt()
            receipt.messageClientID = "message"
            payload = try receipt.serializedData()
        }
        try await synchronizer.processIncoming(
            ProtocolEnvelope(type: type, clientID: "message", timestamp: 1, conversationID: "conversation", senderDeviceID: "other-device", payload: payload),
            deviceID: "device"
        )
        #expect(try database.messages(in: "conversation").first?.status == status)
    }
}

@Test
func expiredTokenIsRefreshedOnceForMailboxAndReconnect() async throws {
    let body = Data(#"{"cursor":0,"items":[]}"#.utf8)
    let http = FakeHTTPClient(responses: [
        HTTPResponse(statusCode: 401, data: Data()),
        HTTPResponse(statusCode: 200, data: body),
    ])
    let provider = FakeTokenProvider()
    let client = ServerMailboxHTTPClient(http: http, tokenProvider: provider)
    _ = try await client.pending(cursor: 0)
    #expect(await provider.refreshes() == 1)
    #expect(await http.headers() == ["Bearer expired", "Bearer fresh"])

    let transport = FakeTransport()
    await transport.setFailFirstConnection()
    let manager = ConnectionManager(transport: transport)
    try await manager.connect(accessToken: "expired", deviceID: "device", tokenProvider: provider)
    #expect(await provider.refreshes() == 2)
    #expect(await manager.state == .connected)
}

private func textPayload(_ text: String) -> Data {
    var message = Telegraphe_V1_TextMessage()
    message.text = text
    return (try? message.serializedData()) ?? Data()
}

extension FakeTransport {
    func setFailFirstConnection() {
        failFirstConnection = true
    }
}
