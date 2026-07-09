import SwiftUI
import ASBMUtilCore

struct MDMServerListView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = MDMServersViewModel()
    @State private var selectedServerID: String?
    @State private var showingDetail = false

    private var selectedServer: MdmServerWithId? {
        viewModel.servers.first { $0.id == selectedServerID }
    }

    private var navigationTitle: String {
        // Avoid "Servers (0)" while loading or after an error — the count isn't known yet.
        if viewModel.isLoading || viewModel.errorMessage != nil { return "Servers" }
        return "Servers (\(viewModel.servers.count))"
    }

    var body: some View {
        mainContent
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingDetail.toggle()
                    } label: {
                        Label("Details", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the server details")
                    .disabled(selectedServerID == nil)
                }
                ToolbarItem {
                    Button {
                        Task { await loadServers() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Reload the server list")
                    .disabled(viewModel.isLoading)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .inspector(isPresented: $showingDetail) {
                if let server = selectedServer {
                    MDMServerDetailView(server: server)
                        .environment(appViewModel)
                        .inspectorColumnWidth(min: 380, ideal: 500, max: 600)
                }
            }
            .onChange(of: selectedServerID) { _, newValue in
                showingDetail = newValue != nil
            }
            .task {
                if viewModel.servers.isEmpty && !viewModel.isLoading {
                    await loadServers()
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading servers...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadServers() } }
            }
        } else if viewModel.servers.isEmpty {
            ContentUnavailableView("No Servers", systemImage: "server.rack")
        } else {
            serverTable
        }
    }

    private var serverTable: some View {
        Table(viewModel.servers, selection: $selectedServerID) {
            TableColumn("Name") { (server: MdmServerWithId) in
                Text(server.serverName ?? "-")
            }
            .width(min: 120, ideal: 200)

            TableColumn("Type") { (server: MdmServerWithId) in
                Text(server.serverType ?? "-")
            }
            .width(min: 80, ideal: 120)

            TableColumn("ID") { (server: MdmServerWithId) in
                Text(server.id)
                    .fontDesign(.monospaced)
                    .font(.caption)
            }
            .width(min: 100, ideal: 200)
        }
    }

    private func loadServers() async {
        do {
            let client = try await appViewModel.ensureConnected()
            await viewModel.loadServers(client: client)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
