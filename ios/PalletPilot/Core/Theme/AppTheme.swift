import SwiftUI

/// Shared visual language extracted from `design/screenshots/`.
/// Light screens use the iOS grouped background + white cards;
/// capture screens overlay dark translucent pills on the camera preview.
enum AppTheme {
    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 16

    // MARK: - Layout
    static let cardRadius: CGFloat = 16
    static let pillRadius: CGFloat = 22
    static let buttonRadius: CGFloat = 14
    static let rowThumbnail: CGFloat = 56
    static let cardSpacing: CGFloat = 12

    // MARK: - Light surfaces
    static let groupedBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let sectionHeader = Color(.secondaryLabel)
    static let footnote = Color(.secondaryLabel)

    // MARK: - Brand / status
    static let primary = Color(.systemBlue)
    static let profit = Color(red: 0.13, green: 0.6, blue: 0.3)
    static let warningBackground = Color(red: 1.0, green: 0.95, blue: 0.87)
    static let warningText = Color(red: 0.62, green: 0.36, blue: 0.0)
    static let reviewPillBackground = Color(red: 1.0, green: 0.93, blue: 0.8)
    static let confidencePillBackground = Color(red: 0.9, green: 0.97, blue: 0.9)
    static let confidencePillText = Color(red: 0.15, green: 0.55, blue: 0.25)

    // MARK: - Capture (dark overlay)
    static let captureBackground = Color(red: 0.23, green: 0.19, blue: 0.16)
    static let capturePill = Color.black.opacity(0.55)
    static let capturePillBorder = Color.white.opacity(0.18)
    static let recordRed = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let detectingBlue = Color(red: 0.25, green: 0.7, blue: 1.0)

    // MARK: - Type
    static func price(_ amount: Double?, currency: String = "$") -> String {
        guard let amount else { return "No price" }
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(currency)\(Int(amount))"
        }
        return String(format: "\(currency)%.2f", amount)
    }

    static func conditionLabel(_ condition: String) -> String {
        switch condition {
        case "like_new": return "Like new"
        case "unknown": return "Unknown"
        default: return condition.capitalized
        }
    }
}
