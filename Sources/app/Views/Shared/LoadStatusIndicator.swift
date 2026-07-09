import SwiftUI

/// Compact toolbar indicator for the streaming device load: shows a live count with a
/// Pause control while loading, and a Resume control while paused. Renders nothing when
/// the load is idle or complete, so it quietly disappears once data is in.
///
/// Cursor pagination gives no total up front, so this pairs an indeterminate spinner with
/// a running count — the HIG-appropriate pattern for work of unknown length.
struct LoadStatusIndicator: View {
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        switch appViewModel.deviceLoadState {
        case .loading:
            pill {
                ProgressView().controlSize(.small)
                Text("Loaded \(appViewModel.devices.count) devices…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    appViewModel.pauseLoad()
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                .help("Pause loading")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading devices")
            .accessibilityValue("\(appViewModel.devices.count) loaded")

        case .paused:
            pill {
                Text("Paused · \(appViewModel.devices.count) loaded")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    appViewModel.resumeLoad()
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                .help("Resume loading")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading paused")
            .accessibilityValue("\(appViewModel.devices.count) loaded")

        case .idle, .complete, .failed:
            EmptyView()
        }
    }

    /// Insets the indicator's content so the text and controls aren't cramped against
    /// the edges of the toolbar's own item background. No extra background/capsule here —
    /// the toolbar already draws one, and layering a second cast a visible shadow.
    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Spacing.sm) {
            content()
        }
        .padding(.horizontal, Spacing.sm)
    }
}
