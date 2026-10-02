import Foundation
import Security

struct Connection: Codable, Equatable {
    let version: Int
    let endpoint: String
    let readToken: String
    let encryptionKey: String
    func validate() throws {
        guard version == 1, let url = URL(string: endpoint), url.scheme == "https",
              let host = url.host, host.hasSuffix(".convex.site"),
              url.path == "/v1/snapshot", url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil,
              readToken.count >= 40, readToken.count <= 256,
              Data(base64Encoded: encryptionKey)?.count == 32 else { throw SnapshotError.invalid }
    }
}
struct KeychainFailure: Error { let status: OSStatus }
struct ConnectionKeychain {
    /// The app's bundle identifier, so each build identity keeps its own credential.
    static let service = Bundle.main.bundleIdentifier ?? "finance"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "connection-v1"]
    }
    static func load() throws -> Connection? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        guard let data = result as? Data else { throw SnapshotError.invalid }
        let connection = try JSONDecoder().decode(Connection.self, from: data)
        try connection.validate()
        return connection
    }
    static func save(_ connection: Connection) throws {
        try connection.validate()
        let data = try JSONEncoder().encode(connection)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            let added = SecItemAdd(insertion as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainFailure(status: added) }
        } else if status != errSecSuccess { throw KeychainFailure(status: status) }
    }
}
