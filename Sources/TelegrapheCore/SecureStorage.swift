import Foundation
import SkipKeychain

public protocol SecureStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

public struct KeychainSecureStorage: SecureStorage {
    public init() {}
    public func string(forKey key: String) -> String? {
        try? Keychain.shared.string(forKey: key)
    }
    public func set(_ value: String, forKey key: String) throws {
        try Keychain.shared.set(value, forKey: key)
    }
    public func removeValue(forKey key: String) throws {
        try Keychain.shared.removeValue(forKey: key)
    }
}
