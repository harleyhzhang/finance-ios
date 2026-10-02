import Foundation

/// Gross personal market estimate; deliberately separate from the issuer's tax FMV.
struct EquityValuation: Codable, Equatable {
    let policy: String
    let provider: String
    let priceUsdMinor: Int64
    let priceAsOf: String
    let priceSourceURL: String
    let awardedUnits: Int64
    let serviceVestedUnits: Int64
    let settledUnits: Int64
    let unitsAsOf: String
    let unitsSourceURL: String
    let shareBasis: String

    func amountMinor(asOf: String) throws -> Int64 {
        guard Snapshot.date(asOf) != nil, policy == "forge-service-vested-v1", provider == "Forge",
              shareBasis == "issuer-reference-price-proxy", priceUsdMinor > 0,
              Snapshot.date(priceAsOf) != nil, Snapshot.date(unitsAsOf) != nil,
              priceAsOf <= asOf, unitsAsOf <= asOf,
              priceSourceURL.range(of: #"^https://forgeglobal\.com/[a-z0-9-]+_stock/$"#, options: .regularExpression) != nil,
              unitsSourceURL.hasPrefix("https://app.carta.com/"),
              awardedUnits >= serviceVestedUnits, serviceVestedUnits >= settledUnits, settledUnits >= 0
        else { throw SnapshotError.invalid }
        let (amount, overflow) = (serviceVestedUnits - settledUnits).multipliedReportingOverflow(by: priceUsdMinor)
        guard !overflow, amount < 1_000_000_000_000 else { throw SnapshotError.invalid }
        return amount
    }
}
