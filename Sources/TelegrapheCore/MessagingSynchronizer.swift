import Foundation

public actor MessagingSynchronizer {
    public let database: LocalDatabase
    public let transport: any MessageTransport
    public let mailbox: any MailboxHTTPClient
    public let codec: any ProtocolCodec

    public init(
        database: LocalDatabase,
        transport: any MessageTransport,
        mailbox: any MailboxHTTPClient,
        codec: any ProtocolCodec = ProtobufProtocolCodec()
    ) {
        self.database = database
        self.transport = transport
        self.mailbox = mailbox
        self.codec = codec
    }

    public func synchronize(accessToken: String, deviceID: String) async throws {
        try await transport.connect(accessToken: accessToken, deviceID: deviceID)
        try await recover(accessToken: accessToken, deviceID: deviceID)
        while !Task.isCancelled {
            try await process(try await transport.receive(), accessToken: accessToken, deviceID: deviceID)
        }
    }

    public func stop() async {
        await transport.close()
    }

    private func recover(accessToken: String, deviceID: String) async throws {
        let current = try database.cursor(deviceID: deviceID)
        let result = try await mailbox.pending(cursor: current, accessToken: accessToken)
        for item in result.items {
            try await process(try codec.decode(item.envelope), accessToken: accessToken, deviceID: deviceID)
            try await mailbox.acknowledge(clientID: item.clientID, accessToken: accessToken)
            try database.setCursor(deviceID: deviceID, cursor: item.id)
        }
    }

    private func process(
        _ envelope: ProtocolEnvelope,
        accessToken: String,
        deviceID: String
    ) async throws {
        switch envelope.type {
        case 3:
            try await receiveText(envelope, deviceID: deviceID)
        case 4:
            let ack = try Telegraphe_V1_ServerAck(serializedBytes: envelope.payload)
            try database.updateMessageStatus(id: ack.messageClientID, status: ack.accepted ? .sent : .failed)
        case 5, 6:
            let receipt = try Telegraphe_V1_Receipt(serializedBytes: envelope.payload)
            try database.updateMessageStatus(
                id: receipt.messageClientID,
                status: envelope.type == 5 ? .delivered : .read
            )
        default:
            break
        }
    }

    private func receiveText(_ envelope: ProtocolEnvelope, deviceID: String) async throws {
        let text = try Telegraphe_V1_TextMessage(serializedBytes: envelope.payload)
        let conversation = try database.conversation(id: envelope.conversationID)
        let senderID = conversation?.otherUserID ?? envelope.senderDeviceID
        _ = try database.insertIncomingMessage(
            id: envelope.clientID,
            conversationID: envelope.conversationID,
            senderUserID: senderID,
            text: text.text,
            timestamp: envelope.timestamp
        )
        var receipt = Telegraphe_V1_Receipt()
        receipt.messageClientID = envelope.clientID
        receipt.targetDeviceID = envelope.senderDeviceID
        let receiptEnvelope = ProtocolEnvelope(
            type: 5,
            clientID: envelope.clientID,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            conversationID: envelope.conversationID,
            senderDeviceID: deviceID,
            encryptionVersion: 0,
            payload: try receipt.serializedData()
        )
        try await transport.send(receiptEnvelope)
    }
}
