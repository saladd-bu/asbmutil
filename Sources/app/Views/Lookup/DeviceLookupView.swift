import SwiftUI
import UniformTypeIdentifiers
import ASBMUtilCore

struct DeviceLookupView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var showFilePicker = false
    @State private var pendingImport: [String] = []
    @State private var showImportPreview = false
    @FocusState private var inputFocused: Bool

    // Owned by AppViewModel so typed serials and results survive tab switches.
    private var viewModel: DeviceLookupViewModel { appViewModel.deviceLookupModel }

    var body: some View {
        @Bindable var viewModel = appViewModel.deviceLookupModel

        VStack(alignment: .leading, spacing: 0) {
            // Input area
            LabeledSection("Serial Numbers") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SerialInputField(
                        text: $viewModel.serialInput,
                        isDisabled: !viewModel.importedSerials.isEmpty,
                        isFocused: $inputFocused
                    )
                    .accessibilityLabel("Device serial numbers")
                    .accessibilityHint("Enter serial numbers separated by commas, spaces, or new lines. Press Command-Return to look up.")

                    HStack {
                        Button("Look Up") {
                            Task { await lookup() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(viewModel.serialNumbers.isEmpty || viewModel.isLoading)

                        if viewModel.isLoading {
                            ProgressView().controlSize(.small)
                        }

                        Button("Import CSV") { showFilePicker = true }

                        if !viewModel.importedSerials.isEmpty {
                            Text("\(viewModel.importedSerials.count) serials imported")
                                .foregroundStyle(.secondary).font(.caption)
                            Button("Clear") { viewModel.importedSerials.removeAll() }
                                .buttonStyle(.borderless).font(.caption)
                        }

                        Spacer()

                        Text("\(viewModel.serialNumbers.count) serial(s)")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            .padding()

            Divider()

            // Results
            if let error = viewModel.errorMessage {
                InlineHint(.danger, error, isLive: false)
                    .padding()
                Spacer()
            } else if !viewModel.results.isEmpty {
                Text("\(viewModel.assignedCount)/\(viewModel.results.count) devices have server assignments")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.top, Spacing.sm)
                    .accessibilityAddTraits(.updatesFrequently)

                Table(viewModel.results) {
                    TableColumn("Serial") { (r: DeviceMdmResult) in
                        Text(r.serialNumber).fontDesign(.monospaced)
                    }.width(min: 110, ideal: 140)

                    TableColumn("Server") { (r: DeviceMdmResult) in
                        Label {
                            Text(serverLabel(for: r))
                        } icon: {
                            Image(systemName: statusSymbol(for: r))
                                .foregroundStyle(statusColor(for: r))
                        }
                        .help(helpText(for: r))
                        .accessibilityLabel("\(serverLabel(for: r))")
                    }.width(min: 120, ideal: 180)

                    TableColumn("Type") { (r: DeviceMdmResult) in
                        Text(r.assignedMdm?.serverType ?? "-")
                    }.width(min: 60, ideal: 100)

                    TableColumn("Server ID") { (r: DeviceMdmResult) in
                        Text(r.assignedMdm?.id ?? "-")
                            .fontDesign(.monospaced).font(.caption)
                    }.width(min: 80, ideal: 200)
                }
            } else {
                ContentUnavailableView("No Lookups Yet", systemImage: "magnifyingglass",
                                       description: Text("Enter serial numbers above and press Look Up to see each device's MDM server assignment."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Device Lookup")
        .onAppear { if viewModel.results.isEmpty && !viewModel.isLoading { inputFocused = true } }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first,
               let parsed = appViewModel.deviceLookupModel.readCSV(from: url) {
                pendingImport = parsed
                showImportPreview = true
            }
        }
        .sheet(isPresented: $showImportPreview) {
            CSVImportView(serials: pendingImport) { confirmed in
                appViewModel.deviceLookupModel.importedSerials = confirmed
            }
        }
    }

    private func lookup() async {
        do {
            let client = try await appViewModel.ensureConnected()
            await appViewModel.deviceLookupModel.lookup(client: client)
        } catch {
            appViewModel.deviceLookupModel.errorMessage = error.localizedDescription
        }
    }

    private func serverLabel(for r: DeviceMdmResult) -> String {
        switch r.status {
        case .assigned: return r.assignedMdm?.serverName ?? r.assignedMdm?.id ?? "Assigned"
        case .notAssigned: return "Not assigned"
        case .notFound: return "Not found"
        case .error: return "Error"
        }
    }

    /// Pair each lookup outcome with an icon (not hue alone) so "Not assigned",
    /// "Not found", and "Error" are distinguishable without color (WCAG 1.4.1).
    private func statusSymbol(for r: DeviceMdmResult) -> String {
        switch r.status {
        case .assigned: return "checkmark.circle.fill"
        case .notAssigned: return "minus.circle"
        case .notFound: return "questionmark.circle"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for r: DeviceMdmResult) -> Color {
        switch r.status {
        case .assigned: return .green
        case .notAssigned: return .secondary
        case .notFound: return .secondary
        case .error: return .red
        }
    }

    /// A non-empty tooltip: the error if any, otherwise the full server name/id (useful
    /// when the cell truncates), otherwise the status label. Never an empty string.
    private func helpText(for r: DeviceMdmResult) -> String {
        if let error = r.errorMessage, !error.isEmpty { return error }
        if let mdm = r.assignedMdm { return mdm.serverName ?? mdm.id }
        return serverLabel(for: r)
    }
}

