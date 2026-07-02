import SwiftUI
import ASBMUtilCore

struct SidebarView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Binding var selection: NavigationSection?

    var body: some View {
        @Bindable var vm = appViewModel

        List(selection: $selection) {
            Section("Overview") {
                Label("Dashboard", systemImage: NavigationSection.dashboard.icon)
                    .tag(NavigationSection.dashboard)
            }

            Section("Browse") {
                Label("Devices", systemImage: NavigationSection.devices.icon)
                    .tag(NavigationSection.devices)
                Label("Servers", systemImage: NavigationSection.mdmServers.icon)
                    .tag(NavigationSection.mdmServers)
            }

            Section("Actions") {
                Label("Assignments", systemImage: NavigationSection.assignments.icon)
                    .tag(NavigationSection.assignments)
                Label("Device Lookup", systemImage: NavigationSection.deviceLookup.icon)
                    .tag(NavigationSection.deviceLookup)
                Label("Batch Status", systemImage: NavigationSection.batchStatus.icon)
                    .tag(NavigationSection.batchStatus)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        .safeAreaInset(edge: .bottom) {
            profileSection
        }
    }

    private var profileSection: some View {
        @Bindable var vm = appViewModel
        return VStack(spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                connectionStatusDot
                Picker("Profile", selection: $vm.activeProfile) {
                    if appViewModel.profiles.isEmpty {
                        Text("default").tag("default")
                    }
                    ForEach(appViewModel.profiles, id: \.name) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }
                .labelsHidden()
                .controlSize(.regular)
                .onChange(of: appViewModel.activeProfile) { _, newValue in
                    Task { await appViewModel.switchProfile(newValue) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var connectionStatusDot: some View {
        // Shape differs per state (filled / dashed / hollow) so the connection
        // status isn't conveyed by color alone — WCAG 1.4.1.
        Image(systemName: connectionSymbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(connectionColor)
            .frame(width: 12, height: 12)
            .accessibilityLabel("Connection: \(connectionLabel)")
            .help(connectionLabel)
    }

    private var connectionColor: Color {
        // Native system colors: this is a standalone indicator dot with no text
        // on it, so the WCAG text-contrast palette doesn't apply — the bright
        // system hues read better. State is also distinguished by symbol shape
        // (see connectionSymbol) plus the accessibilityLabel/help below.
        switch appViewModel.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var connectionSymbol: String {
        switch appViewModel.connectionState {
        case .connected: return "circle.fill"
        case .connecting: return "circle.dotted"
        case .disconnected: return "circle"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var connectionLabel: String {
        switch appViewModel.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}
