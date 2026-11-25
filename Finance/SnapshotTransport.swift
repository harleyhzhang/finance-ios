import CryptoKit
import Foundation

struct EncryptedEnvelope: Codable { let version: Int; let algorithm: String; let combined: String }
struct SnapshotResponse: Codable {
    let revision: Int
    let capturedAt: String
    let digest: String
    let envelope: EncryptedEnvelope
    func decrypt(using connection: Connection) throws -> Snapshot {
        guard revision > 0, envelope.version == 1, envelope.algorithm == "AES-256-GCM",
              let combined = Data(base64Encoded: envelope.combined), combined.count <= 750_000,
              let key = Data(base64Encoded: connection.encryptionKey), key.count == 32,
              SHA256.hash(data: combined).map({ String(format: "%02x", $0) }).joined() == digest
        else { throw SnapshotError.invalidResponse }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: SymmetricKey(data: key))
        let snapshot = try Snapshot.decode(clear)
        guard snapshot.capturedAt == capturedAt else { throw SnapshotError.invalidResponse }
        return snapshot
    }
}
/// One sealed month of history. Immutable and content-addressed: the phone
/// keeps it by digest and only downloads months it has never seen.
struct HistoryChunkResponse: Codable {
    let digest: String
    let envelope: EncryptedEnvelope
    func open(month: String, using connection: Connection) throws -> [HistoryValue] {
        guard envelope.version == 1, envelope.algorithm == "AES-256-GCM",
              let combined = Data(base64Encoded: envelope.combined), combined.count <= 64_000,
              let key = Data(base64Encoded: connection.encryptionKey), key.count == 32,
              SHA256.hash(data: combined).map({ String(format: "%02x", $0) }).joined() == digest
        else { throw SnapshotError.invalidResponse }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: SymmetricKey(data: key))
        struct Body: Codable { let month: String; let history: [HistoryValue] }
        let body = try JSONDecoder().decode(Body.self, from: clear)
        guard body.month == month, body.history.allSatisfy({ $0.date.hasPrefix(month + "-") }) else {
            throw SnapshotError.invalidResponse
        }
        return body.history
    }
}
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
protocol SnapshotFetching {
    func fetch(_ connection: Connection, digest: String?) async throws -> SnapshotResponse?
    func fetchChunk(_ connection: Connection, digest: String) async throws -> HistoryChunkResponse
}
struct SnapshotTransport: SnapshotFetching {
    func fetchChunk(_ connection: Connection, digest: String) async throws -> HistoryChunkResponse {
        try connection.validate()
        guard digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              connection.endpoint.hasSuffix("/v1/snapshot"),
              let url = URL(string: String(connection.endpoint.dropLast("/v1/snapshot".count)) + "/v1/history/" + digest)
        else { throw SnapshotError.invalid }
        guard let data = try await get(url, connection: connection, digest: nil) else { throw SnapshotError.invalidResponse }
        return try JSONDecoder().decode(HistoryChunkResponse.self, from: data)
    }
    func fetch(_ connection: Connection, digest: String?) async throws -> SnapshotResponse? {
        try connection.validate()
        guard let url = URL(string: connection.endpoint) else { throw SnapshotError.invalid }
        guard let data = try await get(url, connection: connection, digest: digest) else { return nil }
        return try JSONDecoder().decode(SnapshotResponse.self, from: data)
    }
    private func get(_ url: URL, connection: Connection, digest: String?) async throws -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("Bearer \(connection.readToken)", forHTTPHeaderField: "Authorization")
        if let digest { request.setValue("\"\(digest)\"", forHTTPHeaderField: "If-None-Match") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw SnapshotError.invalidResponse }
        if http.statusCode == 304 { return nil }
        if http.statusCode == 401 { throw SnapshotError.unauthorized }
        guard http.statusCode == 200 else { throw SnapshotError.unavailable }
        guard http.expectedContentLength <= 1_000_000 else { throw SnapshotError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_000_000 else { throw SnapshotError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}
