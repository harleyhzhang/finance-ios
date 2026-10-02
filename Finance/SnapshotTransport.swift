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
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
protocol SnapshotFetching {
    func fetch(_ connection: Connection, digest: String?) async throws -> SnapshotResponse?
}
struct SnapshotTransport: SnapshotFetching {
    func fetch(_ connection: Connection, digest: String?) async throws -> SnapshotResponse? {
        try connection.validate()
        guard let url = URL(string: connection.endpoint) else { throw SnapshotError.invalid }
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
        return try JSONDecoder().decode(SnapshotResponse.self, from: data)
    }
}
