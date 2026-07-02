import SwiftUI

// MARK: - Status kind (color/symbol bucket)

/// The visual bucket a raw API status string maps into. ASBMUtil's status
/// vocabulary (ASSIGNED, IN_PROGRESS, TIMEOUT, …) is preserved verbatim — this
/// enum only groups those raw values into a color + SF Symbol.
///
/// Colors are Apple's **native system colors**, not hand-authored hex. They
/// adapt to Light/Dark and to the "Increase Contrast" accessibility setting on
/// their own, and they read as at-home on macOS. Because the meaning is carried
/// by the neutral-colored **text label** plus the **icon shape** (never by hue
/// alone — WCAG 1.4.1), the accent color is reinforcement, so it doesn't need to
/// meet the 4.5:1 text-contrast bar.
enum StatusKind: CaseIterable {
    case success   // ASSIGNED, COMPLETE(D), ACTIVE, CONNECTED
    case warning   // UNASSIGNED, PENDING, IN_PROGRESS
    case failure   // FAILED, ERROR, EXPIRED, CANCELED
    case timeout   // TIMEOUT
    case neutral   // everything else

    /// Bucket a raw API/connection status string. Matching is on the uppercased
    /// value, exactly as `StatusBadge` did before — behavior is unchanged.
    init(apiStatus: String) {
        switch apiStatus.uppercased() {
        case "ASSIGNED", "COMPLETE", "COMPLETED", "ACTIVE", "CONNECTED":
            self = .success
        case "UNASSIGNED", "PENDING", "IN_PROGRESS":
            self = .warning
        case "FAILED", "ERROR", "EXPIRED", "CANCELED":
            self = .failure
        case "TIMEOUT":
            self = .timeout
        default:
            self = .neutral
        }
    }

    /// Native system accent color for this bucket (adapts to appearance).
    var color: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        case .timeout: return .purple
        case .neutral: return .secondary
        }
    }

    /// SF Symbol paired with the color so status is distinguishable without
    /// relying on hue (WCAG 1.4.1 Use of Color).
    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .timeout: return "clock.badge.exclamationmark.fill"
        case .neutral: return "circle.fill"
        }
    }
}

// MARK: - Semantic colors

extension Color {
    /// Native, appearance-adaptive status accents. Use for icons, borders, and
    /// soft fills — not as text on a tint (system green/orange are ~2:1 as text;
    /// keep status text in `.primary`/`.secondary` and let these accent it).
    static let statusSuccess = Color.green
    static let statusWarning = Color.orange
    static let statusError   = Color.red
}

// MARK: - Status label formatting

enum StatusStyle {
    /// Human-readable form of a raw API status. Keeps ASBMUtil's vocabulary but
    /// presents it in title case for legibility (HIG; WCAG 3.1):
    /// `IN_PROGRESS` → "In Progress", `ASSIGNED` → "Assigned", `TIMEOUT` → "Timeout".
    /// Bucketing/matching still uses the raw value, so nothing else changes.
    static func displayLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }
        // Fast path for ASBMUtil's known status vocabulary (the values that show
        // up on every table/chart row); fall back to the general transform for
        // anything the API returns that we haven't seen.
        if let known = knownLabels[trimmed.uppercased()] { return known }
        return trimmed
            .split(whereSeparator: { $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static let knownLabels: [String: String] = [
        "ASSIGNED": "Assigned", "UNASSIGNED": "Unassigned",
        "COMPLETE": "Complete", "COMPLETED": "Completed",
        "ACTIVE": "Active", "CONNECTED": "Connected",
        "PENDING": "Pending", "IN_PROGRESS": "In Progress",
        "FAILED": "Failed", "ERROR": "Error", "EXPIRED": "Expired",
        "CANCELED": "Canceled", "TIMEOUT": "Timeout",
    ]
}
