import CryptoKit
import Foundation
import Security

/// Keep diagnostics free of URLs, response bodies and credentials.
struct RefreshReport: Codable {
    let outcome: String
    let revision: Int
    let capturedAt: String?
    let errorDomain: String?
    let errorCode: Int?
}

enum RefreshFailure {
    static func message(for error: Error) -> String {
        let saved = " Your saved snapshot is unchanged."
        if let keychain = error as? KeychainFailure {
            return keychain.status == errSecInteractionNotAllowed
                ? "Unlock your iPhone, then refresh again." + saved
                : "Finance couldn't access its saved connection. Reinstall a signed build." + saved
        }
        if let error = error as? SnapshotError {
            switch error {
            case .noConnection: return "Open your Finance connection file once, then pull to refresh."
            case .unauthorized: return "Your connection needs to be renewed." + saved
            case .unavailable: return "The snapshot service is unavailable. Try again shortly." + saved
            case .rollback: return "The update is older than your saved snapshot." + saved
            case .invalid, .invalidResponse: return "The update couldn't be validated." + saved
            }
        }
        if error is DecodingError { return "The update couldn't be read. Update Finance and try again." + saved }
        if error is CryptoKitError { return "The update couldn't be unlocked. Reopen your Finance connection file." + saved }
        let native = error as NSError
        if native.domain == NSURLErrorDomain { return "Finance couldn't reach the snapshot service. Check your connection and try again." + saved }
        if native.domain == NSCocoaErrorDomain { return "Finance couldn't save the update. Unlock your iPhone and check free storage." + saved }
        return "Couldn't update right now." + saved
    }
}
