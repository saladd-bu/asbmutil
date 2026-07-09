import SwiftUI

/// The single source of truth for status/severity **color + SF Symbol** across the
/// app. `StatusKind` (raw API-status buckets) and `CalloutKind` (inline hint/callout
/// severities) both resolve their icon and accent through this, so a given severity
/// always renders identically whether it appears in a `StatusBadge`, an `InlineHint`,
/// or a `Callout`.
///
/// Colors are Apple's native system colors — they adapt to Light/Dark and to the
/// "Increase Contrast" setting on their own. Meaning is always carried by the neutral
/// text label plus the icon shape (never hue alone — WCAG 1.4.1), so the color is
/// reinforcement only.
enum Severity {
    case info       // notes, neutral information
    case success    // ASSIGNED, COMPLETE(D), ACTIVE, CONNECTED
    case warning    // UNASSIGNED, PENDING, IN_PROGRESS, cautions
    case failure    // FAILED, ERROR, EXPIRED, CANCELED
    case timeout     // TIMEOUT
    case neutral    // everything else

    var color: Color {
        switch self {
        case .info:    return .blue
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        case .timeout: return .purple
        case .neutral: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .info:    return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .timeout: return "clock.badge.exclamationmark.fill"
        case .neutral: return "circle.fill"
        }
    }
}
