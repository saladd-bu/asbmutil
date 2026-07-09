import SwiftUI

/// A section with a consistent `SectionHeader` heading over a softly-grouped content
/// area. This is the single "titled section" treatment used across the action panes
/// (Assignments, Device Lookup, Batch Status) so section titles read as titles and the
/// grouped content looks the same everywhere.
struct LabeledSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
