import SwiftUI

/// Shared layout spacing scale so padding/insets are consistent across views instead
/// of hand-tuned magic numbers. Values follow the common 4-pt rhythm used on macOS.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}
