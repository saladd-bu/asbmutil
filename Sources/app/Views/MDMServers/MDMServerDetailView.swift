import SwiftUI
import ASBMUtilCore

struct MDMServerDetailView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var devices: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    let server: MdmServerWithId

    var filteredDevices: [String] {
        guard !searchText.isEmpty else { return devices }
        return devices.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Server info
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(server.serverName ?? "Server", level: .prominent)
                Text(server.serverType ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(server.id)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading devices…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Devices", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadDevices() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if devices.isEmpty {
                ContentUnavailableView("No Devices", systemImage: "desktopcomputer",
                                       description: Text("No devices are assigned to this server."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(devices.count) devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, Spacing.sm)

                List(filteredDevices, id: \.self) { serial in
                    Text(serial)
                        .fontDesign(.monospaced)
                        .font(.callout)
                }
                .searchable(text: $searchText, prompt: "Filter")
            }
        }
        .task(id: server.id) {
            await loadDevices()
        }
    }

    private func loadDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            let client = try await appViewModel.ensureConnected()
            devices = try await client.listMdmServerDevices(serverId: server.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
