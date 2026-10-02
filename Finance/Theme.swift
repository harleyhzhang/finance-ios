import SwiftUI

/// The app's only type scale, palette and spacing. Numbers use SF Rounded; labels use the system font.
enum Theme {
    static let headline = Font.system(size: 48, weight: .semibold, design: .rounded)
    static func number(_ style: Font.TextStyle) -> Font { .system(style, design: .rounded, weight: .semibold) }
    static let title = Font.title3.weight(.semibold)
    static let section = Font.title3.weight(.bold)
    static let label = Font.subheadline
    static let caption = Font.caption2

    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let rule = Color(uiColor: .systemGray)
    static let accent = Color.green
    static let gain = Color.green
    static let loss = Color.red

    static let cardRadius: CGFloat = 18
    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 30
}
