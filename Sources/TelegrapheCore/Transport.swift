import Foundation

public struct ProtocolEnvelope: Sendable, Equatable {
    public let type: UInt8
    public let clientID: String
    public let timestamp: Int64
    public let conversationID: String
    public let senderDeviceID: String
    public let payload: Data
    public init(type: UInt8, clientID: String, timestamp: Int64, conversationID: String, senderDeviceID: String, payload: Data) {
        self.type = type; self.clientID = clientID; self.timestamp = timestamp
        self.conversationID = conversationID; self.senderDeviceID = senderDeviceID; self.payload = payload
    }
}

public protocol MessageTransport: Sendable {
    func connect(accessToken: String, deviceID: String) async throws
    func send(_ envelope: ProtocolEnvelope) async throws
    func receive() async throws -> ProtocolEnvelope
    func close() async
}

public protocol WebSocketConnection: Sendable {
    func open(accessToken: String) async throws
    func write(_ data: Data) async throws
    func read() async throws -> Data
    func close() async
}

public protocol ProtocolCodec: Sendable {
    func encode(_ envelope: ProtocolEnvelope) throws -> Data
    func decode(_ data: Data) throws -> ProtocolEnvelope
    func handshake(protocolVersion: UInt32, deviceID: String) throws -> Data
}

public actor ProtocolWebSocketTransport: MessageTransport {
    private let connection: WebSocketConnection
    private let codec: ProtocolCodec
    private var handshaken = false

    public init(connection: WebSocketConnection, codec: ProtocolCodec) {
        self.connection = connection
        self.codec = codec
    }

    public func connect(accessToken: String, deviceID: String) async throws {
        try await connection.open(accessToken: accessToken)
        try await connection.write(try codec.handshake(protocolVersion: 1, deviceID: deviceID))
        _ = try await connection.read()
        handshaken = true
    }

    public func send(_ envelope: ProtocolEnvelope) async throws {
        guard handshaken else { throw TransportError.notConnected }
        try await connection.write(try codec.encode(envelope))
    }

    public func receive() async throws -> ProtocolEnvelope {
        guard handshaken else { throw TransportError.notConnected }
        return try codec.decode(try await connection.read())
    }

    public func close() async {
        handshaken = false
        await connection.close()
    }

}

public actor ReconnectingTransport {
    private let transport: MessageTransport
    private let maxDelay: UInt64
    private var connected = false
    public init(transport: MessageTransport, maxDelay: UInt64 = 30) {
        self.transport = transport; self.maxDelay = maxDelay
    }
    public func connect(accessToken: String, deviceID: String) async throws {
        var delay: UInt64 = 1
        while !connected {
            do {
                try await transport.connect(accessToken: accessToken, deviceID: deviceID)
                connected = true
            } catch {
                try await Task.sleep(for: .seconds(delay))
                delay = min(maxDelay, delay * 2)
            }
        }
    }
    public func send(_ envelope: ProtocolEnvelope) async throws {
        guard connected else { throw TransportError.notConnected }
        try await transport.send(envelope)
    }
    public func disconnect() async {
        connected = false
        await transport.close()
    }
}

public enum TransportError: Error, Equatable {
    case notConnected
    case unsupportedProtocol
    case invalidEnvelope
}
