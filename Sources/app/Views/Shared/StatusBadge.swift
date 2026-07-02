import SwiftUI

/// A status pill: soft native-tinted capsule with a colored icon, a same-hue
/// border, and a title-cased **neutral** label. Meaning is carried by the text
/// and the icon shape (never hue alone — WCAG 1.4.1); the color is a native
/// system accent that adapts to Light/Dark and Increase Contrast on its own.
struct StatusBadge: View {
    let status: String

    private var kind: StatusKind { StatusKind(apiStatus: status) }
    private var label: String { StatusStyle.displayLabel(status) }

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
        }
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(1)
        .minimumScaleFactor(0.8)   // shrink slightly rather than truncate to "…" in tight columns
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(kind.color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(kind.color.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(label)")
    }
}
