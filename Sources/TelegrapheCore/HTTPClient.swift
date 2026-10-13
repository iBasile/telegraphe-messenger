import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol HTTPClient: Sendable {
    func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HTTPResponse
}

public enum HTTPClientError: Error, Equatable {
    case invalidURL
    case networkUnavailable
    case invalidResponse
}

public struct APIConfiguration: Sendable, Equatable {
    public var serverURL: URL
    public init(serverURL: URL = URL(string: "https://telegraphe.basile.dedica-marcq.com")!) {
        self.serverURL = serverURL
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    public let configuration: APIConfiguration
    public init(configuration: APIConfiguration) {
        self.configuration = configuration
    }

    public func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String] = [:]
    ) async throws -> HTTPResponse {
        guard let url = URL(string: path, relativeTo: configuration.serverURL) else {
            throw HTTPClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse
            }
            return HTTPResponse(statusCode: httpResponse.statusCode, data: data)
        } catch let error as HTTPClientError {
            throw error
        } catch {
            throw HTTPClientError.networkUnavailable
        }
    }
}
