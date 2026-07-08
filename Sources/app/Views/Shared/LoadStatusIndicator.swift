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
            HStack(spacing: 8) {
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
            HStack(spacing: 8) {
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
}
