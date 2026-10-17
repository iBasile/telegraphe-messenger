import Foundation

public struct ProtocolEnvelope: Sendable, Equatable {
    public let type: UInt8
    public let clientID: String
    public let timestamp: Int64
    public let conversationID: String
    public let senderDeviceID: String
    public let encryptionVersion: UInt32
    public let payload: Data
    public init(
        type: UInt8,
        clientID: String,
        timestamp: Int64,
        conversationID: String,
        senderDeviceID: String,
        encryptionVersion: UInt32 = 0,
        payload: Data
    ) {
        self.type = type; self.clientID = clientID; self.timestamp = timestamp
        self.conversationID = conversationID; self.senderDeviceID = senderDeviceID
        self.encryptionVersion = encryptionVersion; self.payload = payload
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

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error
}

public actor ConnectionManager {
    public private(set) var state: ConnectionState = .disconnected
    private let transport: any MessageTransport
    private let maxDelay: UInt64
    private var stopped = false

    public init(transport: any MessageTransport, maxDelay: UInt64 = 30) {
        self.transport = transport
        self.maxDelay = maxDelay
    }

    public func connect(accessToken: String, deviceID: String) async {
        stopped = false
        var delay: UInt64 = 1
        while !stopped {
            state = .connecting
            do {
                try await transport.connect(accessToken: accessToken, deviceID: deviceID)
                state = .connected
                return
            } catch {
                state = .error
                let jitter = UInt64.random(in: 0...max(1, delay / 4))
                try? await Task.sleep(for: .milliseconds((delay + jitter) * 1_000))
                delay = min(maxDelay, delay * 2)
            }
        }
    }

    public func disconnect() async {
        stopped = true
        state = .disconnected
        await transport.close()
    }
}

public struct ProtobufProtocolCodec: ProtocolCodec {
    public init() {}

    public func encode(_ envelope: ProtocolEnvelope) throws -> Data {
        var value = Telegraphe_V1_Envelope()
        value.type = Telegraphe_V1_EnvelopeType(rawValue: Int(envelope.type)) ?? .unspecified
        value.clientID = envelope.clientID
        value.timestampMs = envelope.timestamp
        value.conversationID = envelope.conversationID
        value.senderDeviceID = envelope.senderDeviceID
        value.encryptionVersion = envelope.encryptionVersion
        value.payload = envelope.payload
        return try value.serializedData()
    }

    public func decode(_ data: Data) throws -> ProtocolEnvelope {
        let value = try Telegraphe_V1_Envelope(serializedBytes: data)
        guard value.type != .unspecified else { throw TransportError.invalidEnvelope }
        return ProtocolEnvelope(
            type: UInt8(clamping: value.type.rawValue),
            clientID: value.clientID,
            timestamp: value.timestampMs,
            conversationID: value.conversationID,
            senderDeviceID: value.senderDeviceID,
            encryptionVersion: value.encryptionVersion,
            payload: value.payload
        )
    }

    public func handshake(protocolVersion: UInt32, deviceID: String) throws -> Data {
        var hello = Telegraphe_V1_Handshake()
        hello.protocolVersion = protocolVersion
        hello.deviceID = deviceID
        var value = Telegraphe_V1_Envelope()
        value.type = .handshake
        value.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        value.senderDeviceID = deviceID
        value.encryptionVersion = 0
        value.payload = try hello.serializedData()
        return try value.serializedData()
    }
}
