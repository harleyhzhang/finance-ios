import Foundation

enum Format {
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(0)))
    }
    static func percent(_ value: Double) -> String {
        "(" + value.formatted(.number.precision(.fractionLength(1))) + "%)"
    }
    static let shortDate = utc(Date.FormatStyle().month(.abbreviated).day())
    static let monthYear = utc(Date.FormatStyle().month(.abbreviated).year())

    /// "Good morning", or "Good morning, Name" when `FINANCE_OWNER_NAME` is set at build time.
    static func greeting(at date: Date = .now, name: String = ownerName) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        return name.isEmpty ? "Good \(part)" : "Good \(part), \(name)"
    }
    static var ownerName: String {
        (Bundle.main.object(forInfoDictionaryKey: "FinanceOwnerName") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func utc(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var style = style
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return style
    }
}
