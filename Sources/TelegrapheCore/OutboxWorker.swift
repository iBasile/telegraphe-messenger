import Foundation

public actor OutboxWorker {
    public let database: LocalDatabase
    public let transport: any MessageTransport
    public let deviceID: String
    public init(database: LocalDatabase, transport: any MessageTransport, deviceID: String) {
        self.database = database
        self.transport = transport
        self.deviceID = deviceID
    }

    public func sendPending() async {
        guard let messages = try? database.pendingOutbox() else { return }
        for message in messages {
            do {
                guard let conversation = try database.conversation(id: message.conversationID) else { continue }
                var text = Telegraphe_V1_TextMessage()
                text.recipientUserID = conversation.otherUserID
                text.text = message.text
                let envelope = ProtocolEnvelope(
                    type: 3,
                    clientID: message.id,
                    timestamp: message.timestamp,
                    conversationID: message.conversationID,
                    senderDeviceID: deviceID,
                    encryptionVersion: 0,
                    payload: try text.serializedData()
                )
                try await transport.send(envelope)
            } catch {
                try? database.recordRetry(id: message.id, error: "transport")
            }
        }
    }
}
