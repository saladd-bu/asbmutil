import SwiftUI

/// A consistent section/pane header, so the app stops styling the same "header"
/// concept five different ways (bare `.headline`, uppercase captions, ad-hoc
/// `.title3`, GroupBox labels). Pick the level that matches the context:
///
/// - `.prominent` — a pane or inspector title (`.title3`, semibold).
/// - `.standard`  — a card or grouped-section title (`.headline`). The default.
/// - `.dense`     — a small field-group label inside a detail form
///   (uppercase caption, secondary) — the established look from the device detail view.
struct SectionHeader: View {
    enum Level { case prominent, standard, dense }

    let title: String
    var level: Level = .standard

    init(_ title: String, level: Level = .standard) {
        self.title = title
        self.level = level
    }

    var body: some View {
        switch level {
        case .prominent:
            Text(title)
                .font(.title3).fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
        case .standard:
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        case .dense:
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary).textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
