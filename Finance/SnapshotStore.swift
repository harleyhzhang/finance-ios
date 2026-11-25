import Foundation
import SwiftUI

struct CachedSnapshot: Codable { let revision: Int; let digest: String?; let snapshot: Snapshot }
@MainActor final class SnapshotStore: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var syncing = false
    @Published var message: String?
    private var revision = 0
    private var digest: String?
    private let cacheURL: URL
    private let chunkDirectory: URL
    private let reportURL: URL
    private let transport: any SnapshotFetching
    private let loadConnection: () throws -> Connection?
    init(directory: URL = URL.documentsDirectory, transport: any SnapshotFetching = SnapshotTransport(), loadConnection: @escaping () throws -> Connection? = ConnectionKeychain.load) {
        self.transport = transport
        self.loadConnection = loadConnection
        cacheURL = directory.appending(path: "cache-v2.json")
        chunkDirectory = directory.appending(path: "history-chunks", directoryHint: .isDirectory)
        reportURL = directory.appending(path: "last-refresh.json")
        #if DEBUG
        if DemoSnapshot.isEnabled { snapshot = DemoSnapshot.make(); return }
        #endif
        if let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(CachedSnapshot.self, from: data), (try? cached.snapshot.validate()) != nil {
            snapshot = cached.snapshot; revision = cached.revision; digest = cached.digest
        } else if let data = try? Data(contentsOf: directory.appending(path: "snapshot.json")), let seed = try? Snapshot.decode(data) {
            snapshot = seed
        }
        // Local provisioning only. It never makes a network request on launch.
        for name in ["connection.financeprofile", "connection.worthprofile"] {
            let profile = directory.appending(path: name)
            guard FileManager.default.fileExists(atPath: profile.path) else { continue }
            do { try importConnection(profile); try FileManager.default.removeItem(at: profile) }
            catch let error as KeychainFailure { message = "Keychain unavailable (\(error.status)). Reinstall a signed build." }
            catch { message = "The connection profile could not be installed." }
        }
    }
    func importConnection(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count < 4096 else { throw SnapshotError.invalid }
        let next = try JSONDecoder().decode(Connection.self, from: data)
        if let existing = try ConnectionKeychain.load(), existing.endpoint != next.endpoint || existing.encryptionKey != next.encryptionKey {
            throw SnapshotError.invalid // Explicit reset required before switching environments/keys.
        }
        try ConnectionKeychain.save(next)
    }
    func refresh() async {
        guard !syncing else { return }
        syncing = true
        message = nil
        defer { syncing = false }
        do {
            guard let connection = try loadConnection() else { throw SnapshotError.noConnection }
            guard let response = try await transport.fetch(connection, digest: digest) else {
                recordRefresh(outcome: "unchanged")
                return
            }
            let next = try await assemble(try response.decrypt(using: connection), connection: connection)
            guard response.revision >= revision, snapshot == nil || next.capturedAt >= (snapshot?.capturedAt ?? "") else { throw SnapshotError.rollback }
            if response.revision == revision, let digest, response.digest != digest { throw SnapshotError.invalidResponse }
            let cached = CachedSnapshot(revision: response.revision, digest: response.digest, snapshot: next)
            let data = try JSONEncoder().encode(cached)
            try data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
            snapshot = next; revision = response.revision; digest = response.digest
            recordRefresh(outcome: "updated")
        } catch {
            message = RefreshFailure.message(for: error)
            recordRefresh(outcome: "failed", error: error)
        }
    }
    /// Expands a chunked head: cached months are reused, only unseen months are fetched.
    private func assemble(_ head: Snapshot, connection: Connection) async throws -> Snapshot {
        guard let refs = head.historyChunks else { return head }
        try FileManager.default.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)
        var history: [HistoryValue] = []
        for ref in refs {
            let file = chunkDirectory.appending(path: ref.digest + ".json")
            let chunk: HistoryChunkResponse
            if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(HistoryChunkResponse.self, from: data), cached.digest == ref.digest {
                chunk = cached
            } else {
                chunk = try await transport.fetchChunk(connection, digest: ref.digest)
                try JSONEncoder().encode(chunk).write(to: file, options: [.atomic, .completeFileProtection])
            }
            history += try chunk.open(month: ref.month, using: connection)
        }
        let full = head.with(history: history)
        try full.validate()
        // Drop months no longer referenced so the cache tracks the live head.
        let keep = Set(refs.map { $0.digest + ".json" })
        for name in (try? FileManager.default.contentsOfDirectory(atPath: chunkDirectory.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: chunkDirectory.appending(path: name))
        }
        return full
    }
    private func recordRefresh(outcome: String, error: Error? = nil) {
        let native = error.map { $0 as NSError }
        let report = RefreshReport(outcome: outcome, revision: revision, capturedAt: snapshot?.capturedAt,
                                   errorDomain: native?.domain, errorCode: (error as? KeychainFailure).map { Int($0.status) } ?? native?.code)
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: reportURL, options: [.atomic, .completeFileProtection])
        }
    }
}
