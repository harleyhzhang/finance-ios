import XCTest
import CryptoKit
import Security
@testable import Finance

final class SnapshotTests: XCTestCase {
    func fixture() throws -> Snapshot {
        try Snapshot.decode(Data(#"{"schemaVersion":2,"capturedAt":"2026-09-22T12:00:00.000Z","asOf":"2026-09-22","cadPerUSD":"1.25","fxAsOf":"2026-09-21","accounts":[{"id":"cash","name":"Example","institution":"Example","category":"Cash","currency":"CAD","amountMinor":12500,"note":"Synthetic","asOf":"2026-09-22"}],"history":[{"date":"2026-01-01","totalMinor":10000,"currency":"CAD","source":"synthetic test"}],"notes":[]}"#.utf8))
    }
    func testBusinessFundsBelongOnlyToCashInBreakdown() {
        for category in ["Cash", "Business funds"] {
            XCTAssertEqual(AssetGroup.allCases.filter { $0.includes(category: category) }, [.cash])
        }
        XCTAssertFalse(AssetGroup.cash.includes(category: "Investments"))
        XCTAssertFalse(AssetGroup.cash.includes(category: "Credit cards"))
    }
    func testFamilyInvestmentsBelongToInvestmentsInBreakdown() {
        for category in ["Investments", "Family investments"] {
            XCTAssertEqual(AssetGroup.allCases.filter { $0.includes(category: category) }, [.investments])
        }
    }
    func testBreakdownSortsLargestFirstAndDebtLast() throws {
        let snapshot = try fixture()
        XCTAssertEqual(snapshot.breakdown(in: "CAD").map(\.group), [.cash])
        XCTAssertEqual(snapshot.total(in: "CAD"), 125, accuracy: 1e-9)
        XCTAssertEqual(snapshot.total(in: "USD"), 100, accuracy: 1e-9)
    }
    func testGreetingOmitsEmptyName() {
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        XCTAssertEqual(Format.greeting(at: morning, name: ""), "Good morning")
        XCTAssertEqual(Format.greeting(at: morning, name: "Sam"), "Good morning, Sam")
    }
    func history(days: Int, ending end: String = "2026-09-22") -> [ChartPoint] {
        let last = Snapshot.date(end)!
        return (0...days).reversed().map { offset in
            let date = last.addingTimeInterval(-Double(offset) * 86_400)
            return ChartPoint(id: offset, date: date, value: Double(offset))
        }
    }
    func testOnlyOfferRangesHistoryFills() {
        XCTAssertEqual(Period.available(history: history(days: 365)), [.month, .sixMonths, .ytd, .year])
        XCTAssertEqual(Period.available(history: history(days: 500)), [.month, .sixMonths, .ytd, .year, .all])
        XCTAssertEqual(Period.available(history: history(days: 300)), [.month, .sixMonths, .ytd, .all])
        XCTAssertEqual(Period.available(history: history(days: 10)), [.all])
        XCTAssertEqual(Period.available(history: []), [.all])
    }
    func testMorphStartsAndEndsOnExactCurves() {
        let source = [PlotPoint(id: 0, position: 0, value: 0), PlotPoint(id: 1, position: 0.3, value: 10), PlotPoint(id: 2, position: 1, value: 4)]
        let target = [PlotPoint(id: 0, position: 0, value: 5), PlotPoint(id: 1, position: 0.8, value: 1), PlotPoint(id: 2, position: 1, value: 2)]
        let start = ChartMorph.points(from: source, to: target, progress: 0)
        let end = ChartMorph.points(from: source, to: target, progress: 1)
        XCTAssertEqual(start.map(\.position), [0, 0.3, 0.8, 1])
        for point in source { XCTAssertEqual(ChartMorph.value(at: point.position, in: start), point.value, accuracy: 1e-9) }
        for point in target { XCTAssertEqual(ChartMorph.value(at: point.position, in: end), point.value, accuracy: 1e-9) }
        XCTAssertEqual(ChartMorph.progress(elapsed: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(ChartMorph.progress(elapsed: ChartMorph.duration), 1)
    }
    func testSignedBuildCanUseDeviceKeychain() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "finance.tests", kSecAttrAccount as String: UUID().uuidString]
        var insertion = query
        insertion[kSecValueData as String] = Data("synthetic-test".utf8)
        let result = SecItemAdd(insertion as CFDictionary, nil)
        XCTAssertEqual(result, errSecSuccess, "Simulator runtime tests must use ad-hoc signing for Keychain access")
        defer { SecItemDelete(query as CFDictionary) }
        var read = query
        read[kSecReturnData as String] = true
        var value: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(read as CFDictionary, &value), errSecSuccess)
        XCTAssertEqual(value as? Data, Data("synthetic-test".utf8))
    }
    func testEquityCountsOnlyServiceVestedUnsettledUnits() throws {
        let valuation = EquityValuation(policy: "forge-service-vested-v1", provider: "Forge", priceUsdMinor: 12345,
            priceAsOf: "2026-09-21", priceSourceURL: "https://forgeglobal.com/example_stock/", awardedUnits: 400,
            serviceVestedUnits: 100, settledUnits: 20, unitsAsOf: "2026-09-22", unitsSourceURL: "https://app.carta.com/example",
            shareBasis: "issuer-reference-price-proxy")
        XCTAssertEqual(try valuation.amountMinor(asOf: "2026-09-22"), 987600)
        XCTAssertThrowsError(try valuation.amountMinor(asOf: "2026-09-20"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture())) as? [String: Any])
        let metadata = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valuation))
        var account: [String: Any] = ["id":"rsu-test", "name":"Example RSUs", "institution":"Example", "category":"RSUs", "currency":"USD", "amountMinor":987600, "asOf":"2026-09-22", "note":"Synthetic test", "valuation":metadata]
        object["accounts"] = [account]
        XCTAssertEqual(try Snapshot.decode(JSONSerialization.data(withJSONObject: object)).totalUSD, 9876)
        account["amountMinor"] = 987601
        object["accounts"] = [account]
        XCTAssertThrowsError(try Snapshot.decode(JSONSerialization.data(withJSONObject: object)))
    }
    func testConversionAndRealHistory() throws {
        let snapshot = try fixture()
        XCTAssertEqual(snapshot.totalUSD, 100)
        let points = HistoryProjection.points(snapshot: snapshot, currency: "USD", period: .all)
        XCTAssertEqual(points.map(\.value), [80, 100])
        XCTAssertEqual(points.count, 2) // No fabricated intermediate values.
        XCTAssertGreaterThan(HistoryProjection.domain(points).upperBound, 100)
    }
    func testRejectMalformedDatesAndDuplicateAccounts() throws {
        XCTAssertNil(Snapshot.date("2026-02-30"))
        let data = try JSONEncoder().encode(fixture())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["accounts"] = (object["accounts"] as! [[String: Any]]) + (object["accounts"] as! [[String: Any]])
        XCTAssertThrowsError(try Snapshot.decode(JSONSerialization.data(withJSONObject: object)))
        object["accounts"] = [[String: Any]]()
        XCTAssertThrowsError(try Snapshot.decode(JSONSerialization.data(withJSONObject: object)))
    }
    func testEncryptedRoundTripAndTamperRejection() throws {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let connection = Connection(version: 1, endpoint: "https://test-example.convex.site/v1/snapshot", readToken: String(repeating: "a", count: 48), encryptionKey: keyData.base64EncodedString())
        try connection.validate()
        let snapshot = try fixture()
        let combined = try XCTUnwrap(AES.GCM.seal(JSONEncoder().encode(snapshot), using: key).combined)
        let digest = SHA256.hash(data: combined).map { String(format: "%02x", $0) }.joined()
        let response = SnapshotResponse(revision: 1, capturedAt: snapshot.capturedAt, digest: digest, envelope: EncryptedEnvelope(version: 1, algorithm: "AES-256-GCM", combined: combined.base64EncodedString()))
        XCTAssertEqual(try response.decrypt(using: connection), snapshot)
        let wrongKey = Connection(version: 1, endpoint: connection.endpoint, readToken: connection.readToken, encryptionKey: Data(repeating: 0, count: 32).base64EncodedString())
        XCTAssertThrowsError(try response.decrypt(using: wrongKey))
        let altered = SnapshotResponse(revision: 1, capturedAt: "2026-09-23T12:00:00.000Z", digest: digest, envelope: response.envelope)
        XCTAssertThrowsError(try altered.decrypt(using: connection))
        let badDigest = SnapshotResponse(revision: 1, capturedAt: snapshot.capturedAt, digest: String(repeating: "0", count: 64), envelope: response.envelope)
        XCTAssertThrowsError(try badDigest.decrypt(using: connection))
    }
    func testRejectUnsafeConnectionURLs() {
        for endpoint in ["http://x.convex.site/v1/snapshot", "https://evil.test/v1/snapshot", "https://x.convex.site.evil.test/v1/snapshot", "https://user:pass@x.convex.site/v1/snapshot", "https://x.convex.site/v1/snapshot?token=a"] {
            let connection = Connection(version: 1, endpoint: endpoint, readToken: String(repeating: "a", count: 48), encryptionKey: Data(repeating: 0, count: 32).base64EncodedString())
            XCTAssertThrowsError(try connection.validate())
        }
    }
    @MainActor func testInvalidCacheFallsBackToValidSeedWithoutNetworking() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("corrupt".utf8).write(to: directory.appending(path: "cache-v2.json"))
        let snapshot = try fixture()
        try JSONEncoder().encode(snapshot).write(to: directory.appending(path: "snapshot.json"))
        let store = SnapshotStore(directory: directory)
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertFalse(store.syncing)
    }
    @MainActor func testFailedRefreshPreservesLastGoodCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try fixture()
        let cache = try JSONEncoder().encode(CachedSnapshot(revision: 4, digest: "saved", snapshot: snapshot))
        let url = directory.appending(path: "cache-v2.json")
        try cache.write(to: url)
        let connection = Connection(version: 1, endpoint: "https://test-example.convex.site/v1/snapshot", readToken: String(repeating: "a", count: 48), encryptionKey: Data(repeating: 0, count: 32).base64EncodedString())
        let store = SnapshotStore(directory: directory, transport: FailingTransport(), loadConnection: { connection })
        await store.refresh()
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertEqual(try Data(contentsOf: url), cache)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.syncing)
        let report = try JSONDecoder().decode(RefreshReport.self, from: Data(contentsOf: directory.appending(path: "last-refresh.json")))
        XCTAssertEqual(report.outcome, "failed")
        XCTAssertEqual(report.revision, 4)
        XCTAssertEqual(report.capturedAt, snapshot.capturedAt)
    }

    func testRefreshErrorsGiveActionableMessagesWithoutLeakingDetails() {
        let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                              userInfo: [NSLocalizedDescriptionKey: "secret credential and URL"])
        let message = RefreshFailure.message(for: network)
        XCTAssertTrue(message.contains("Check your connection"))
        XCTAssertFalse(message.contains("secret"))
        XCTAssertTrue(RefreshFailure.message(for: KeychainFailure(status: errSecInteractionNotAllowed)).contains("Unlock your iPhone"))
        XCTAssertTrue(RefreshFailure.message(for: SnapshotError.rollback).contains("older"))
    }

    @MainActor func testRetryAcceptsValidatedUpdateAndClearsOldError() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try fixture()
        try JSONEncoder().encode(snapshot).write(to: directory.appending(path: "snapshot.json"))
        let key = SymmetricKey(size: .bits256)
        let connection = Connection(version: 1, endpoint: "https://test-example.convex.site/v1/snapshot", readToken: String(repeating: "a", count: 48), encryptionKey: key.withUnsafeBytes { Data($0).base64EncodedString() })
        let combined = try XCTUnwrap(AES.GCM.seal(JSONEncoder().encode(snapshot), using: key).combined)
        let response = SnapshotResponse(revision: 5, capturedAt: snapshot.capturedAt, digest: SHA256.hash(data: combined).map { String(format: "%02x", $0) }.joined(), envelope: EncryptedEnvelope(version: 1, algorithm: "AES-256-GCM", combined: combined.base64EncodedString()))
        let store = SnapshotStore(directory: directory, transport: SuccessfulTransport(response: response), loadConnection: { connection })
        store.message = "Previous failure"
        await store.refresh()
        XCTAssertNil(store.message)
        let cache = try JSONDecoder().decode(CachedSnapshot.self, from: Data(contentsOf: directory.appending(path: "cache-v2.json")))
        XCTAssertEqual(cache.revision, 5)
        XCTAssertEqual(cache.snapshot, snapshot)
        let report = try JSONDecoder().decode(RefreshReport.self, from: Data(contentsOf: directory.appending(path: "last-refresh.json")))
        XCTAssertEqual(report.outcome, "updated")
        XCTAssertNil(report.errorDomain)
        XCTAssertNil(report.errorCode)
    }

}

private struct FailingTransport: SnapshotFetching {
    func fetch(_ connection: Connection, digest: String?) async throws -> SnapshotResponse? { throw SnapshotError.unavailable }
}

private struct SuccessfulTransport: SnapshotFetching {
    let response: SnapshotResponse
    func fetch(_ connection: Connection, digest: String?) async throws -> SnapshotResponse? { response }
}
