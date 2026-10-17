import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    public let endpoint: URL
    private var task: URLSessionWebSocketTask?
    private var keepAlive: Task<Void, Never>?

    public init(endpoint: URL) {
        self.endpoint = endpoint
    }

    public func open(accessToken: String) async throws {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        keepAlive?.cancel()
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, let task = self.task else { return }
                await withCheckedContinuation { continuation in
                    task.sendPing { _ in continuation.resume() }
                }
            }
        }
    }

    public func write(_ data: Data) async throws {
        guard let task else { throw TransportError.notConnected }
        try await task.send(.data(data))
    }

    public func read() async throws -> Data {
        guard let task else { throw TransportError.notConnected }
        switch try await task.receive() {
        case .data(let data):
            return data
        case .string:
            throw TransportError.invalidEnvelope
        @unknown default:
            throw TransportError.invalidEnvelope
        }
    }

    public func close() async {
        keepAlive?.cancel()
        keepAlive = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
