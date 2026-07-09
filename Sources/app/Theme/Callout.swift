import SwiftUI

/// Severity of a `Callout` / `InlineHint`, mapped to a native system accent.
/// The message text stays neutral (`.primary`/`.secondary`) for guaranteed
/// legibility; the color rides on the icon and (for `Callout`) a soft fill and
/// border — consistent with `StatusBadge` and with Apple HIG.
enum CalloutKind: CaseIterable {
    case info
    case success
    case warning
    case danger

    /// The shared severity this maps to for color + symbol, so a warning/error here
    /// renders identically to the same status in a `StatusBadge`.
    var severity: Severity {
        switch self {
        case .info:    return .info
        case .success: return .success
        case .warning: return .warning
        case .danger:  return .failure
        }
    }

    var symbol: String { severity.symbol }

    /// Spoken severity prefix so VoiceOver conveys severity even though the text
    /// itself is neutral-colored.
    var accessibilityPrefix: String {
        switch self {
        case .info:    return "Note"
        case .success: return "Success"
        case .warning: return "Warning"
        case .danger:  return "Error"
        }
    }

    /// Native system accent for the icon / fill / border (never the text color).
    var color: Color { severity.color }
}

/// A rounded, tinted callout card: colored icon + optional bold title + message,
/// with an optional smaller caveat line. Text is neutral for legibility; the
/// kind's color rides on the icon, a soft fill, and a hairline border.
struct Callout: View {
    let kind: CalloutKind
    var title: String? = nil
    let message: String
    var caveat: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title).font(.caption.bold())
                }
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat {
                    Text(caveat)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(kind.color.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(kind.accessibilityPrefix): \(title.map { $0 + ". " } ?? "")\(message)\(caveat.map { " " + $0 } ?? "")")
    }
}

/// A compact one-line inline hint: colored icon + neutral text, no fill. For
/// inline form/action feedback (errors, "Saved", "Connected"). Announces itself
/// to VoiceOver since it appears in response to an action.
struct InlineHint: View {
    let kind: CalloutKind
    let text: String
    /// Whether this hint appears transiently in response to an action ("Saved",
    /// "Connected"). Live hints get `.updatesFrequently` so VoiceOver announces them;
    /// pass `false` for persistent text (e.g. a standing error) so it isn't treated as
    /// a live region and re-announced.
    var isLive: Bool = true

    init(_ kind: CalloutKind, _ text: String, isLive: Bool = true) {
        self.kind = kind
        self.text = text
        self.isLive = isLive
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.accessibilityPrefix): \(text)")
        .accessibilityAddTraits(isLive ? .updatesFrequently : [])
    }
}
