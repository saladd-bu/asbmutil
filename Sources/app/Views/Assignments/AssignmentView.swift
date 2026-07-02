import SwiftUI
import UniformTypeIdentifiers
import ASBMUtilCore

struct AssignmentView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = AssignmentViewModel()
    @State private var showFilePicker = false
    @State private var activityHistory: [ActivityDetails] = []

    var body: some View {
        VSplitView {
            actionsSection
            historySection
        }
        .navigationTitle("Assignments")
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.importCSV(from: url)
            }
        }
        .task {
            if viewModel.servers.isEmpty { await loadServers() }
        }
    }

    // MARK: - Actions section

    private var actionsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    GroupBox("Operation") {
                        Picker("Mode", selection: $viewModel.mode) {
                            ForEach(AssignmentMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }

                    GroupBox("Server") {
                        serverPicker
                    }
                }

                GroupBox("Device Serials") {
                    serialInputSection
                }

                executeSection
            }
            .padding()
        }
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private var serverPicker: some View {
        if viewModel.servers.isEmpty {
            HStack {
                Text("No servers loaded").foregroundStyle(.secondary)
                Spacer()
                Button("Load") { Task { await loadServers() } }
            }
        } else {
            Picker("Server", selection: $viewModel.selectedMdmName) {
                Text("Select a server...").tag("")
                ForEach(viewModel.servers, id: \.id) { s in
                    Text(s.serverName ?? s.id).tag(s.serverName ?? "")
                }
            }
        }
    }

    private var serialInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $viewModel.serialInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 50, maxHeight: 70)
                .border(Color.secondary.opacity(0.3))
                .disabled(!viewModel.importedSerials.isEmpty)
                .accessibilityLabel("Device serial numbers")
                .accessibilityHint("Enter serial numbers separated by commas or new lines")

            HStack {
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

            Toggle("Verify serials exist before submitting", isOn: Binding(
                get: { !viewModel.skipVerify },
                set: { viewModel.skipVerify = !$0 }
            ))
            .font(.caption)
            .help("Checks each serial against School/Business Manager first. Serials that don't exist (e.g. not yet registered by the reseller) are reported and excluded rather than silently no-op'd.")

            Toggle("Confirm assignment after submitting", isOn: $viewModel.confirmAfterSubmit)
                .font(.caption)
                .help("After submitting, waits for the activity to finish and re-queries each device to confirm it actually reached the intended MDM. Slower, since it polls until the activity completes.")
        }
    }

    @ViewBuilder
    private var executeSection: some View {
        HStack {
            Button(viewModel.mode == .assign ? "Assign Devices" : "Unassign Devices") {
                Task { await execute() }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.mode == .assign ? .blue : .orange)
            .disabled(!viewModel.canExecute)

            if viewModel.isExecuting { ProgressView().controlSize(.small) }
        }

        if let error = viewModel.errorMessage {
            InlineHint(.danger, error)
        }

        if !viewModel.notFoundSerials.isEmpty || !viewModel.erroredSerials.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    if !viewModel.notFoundSerials.isEmpty {
                        InlineHint(.warning, "\(viewModel.notFoundSerials.count) serial(s) not found — excluded")
                        Text(viewModel.notFoundSerials.joined(separator: ", "))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Not in School/Business Manager yet (not registered by the reseller), or mistyped.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !viewModel.erroredSerials.isEmpty {
                        InlineHint(.warning, "\(viewModel.erroredSerials.count) serial(s) could not be verified — excluded")
                        Text(viewModel.erroredSerials.joined(separator: "\n"))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if let result = viewModel.result {
            GroupBox("Result") {
                HStack {
                    LabeledContent("Activity ID", value: result.id)
                    Spacer()
                    Button("Copy ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.id, forType: .string)
                    }.buttonStyle(.borderless).font(.caption)
                }
                LabeledContent("Status", value: StatusStyle.displayLabel(result.status))
                LabeledContent("Devices", value: "\(result.deviceCount)")
            }
        }

        if viewModel.didConfirm {
            GroupBox("Confirmation") {
                VStack(alignment: .leading, spacing: 6) {
                    if let status = viewModel.confirmStatus {
                        LabeledContent("Activity", value: StatusStyle.displayLabel(status))
                    }
                    if viewModel.confirmStatus == "TIMEOUT" {
                        InlineHint(.warning, "Activity didn't finish in time — couldn't confirm end state.")
                    } else {
                        let total = viewModel.confirmedCount + viewModel.confirmMismatched.count + viewModel.confirmErrored.count
                        let clean = viewModel.confirmMismatched.isEmpty && viewModel.confirmErrored.isEmpty
                        InlineHint(clean ? .success : .warning,
                                   "\(viewModel.confirmedCount)/\(total) device(s) confirmed in the expected state")
                        if !viewModel.confirmMismatched.isEmpty {
                            Text("Not in expected state:").font(.caption2).foregroundStyle(.secondary)
                            Text(viewModel.confirmMismatched.joined(separator: "\n"))
                                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if !viewModel.confirmErrored.isEmpty {
                            Text("Could not confirm:").font(.caption2).foregroundStyle(.secondary)
                            Text(viewModel.confirmErrored.joined(separator: "\n"))
                                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - History section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Session Activity")
                    .font(.headline)
                Spacer()
                if !activityHistory.isEmpty {
                    Text("\(activityHistory.count) activities")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)

            Divider()

            if activityHistory.isEmpty {
                Text("Activities from this session will appear here.")
                    .foregroundStyle(.secondary).font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(activityHistory) { activity in
                    let isUnassign = activity.activityType.contains("UNASSIGN")
                    HStack(spacing: 10) {
                        Image(systemName: isUnassign
                              ? "arrow.uturn.backward.square" : "arrow.right.square")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.deviceSerials.count == 1
                                 ? activity.deviceSerials[0] : "Multiple")
                                .font(.callout).fontWeight(.medium)
                            Text("\(activity.deviceCount) Device\(activity.deviceCount == 1 ? "" : "s") \u{00B7} \(activity.mdmServerName ?? activity.mdmServerId)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: activity.status)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(isUnassign ? "Unassign" : "Assign"), \(activity.deviceSerials.count == 1 ? activity.deviceSerials[0] : "\(activity.deviceCount) devices"), \(activity.mdmServerName ?? activity.mdmServerId), status \(StatusStyle.displayLabel(activity.status))")
                }
            }
        }
    }

    // MARK: - Actions

    private func loadServers() async {
        do {
            let client = try await appViewModel.ensureConnected()
            await viewModel.loadServers(client: client)
        } catch { viewModel.errorMessage = error.localizedDescription }
    }

    private func execute() async {
        do {
            let client = try await appViewModel.ensureConnected()
            await viewModel.execute(client: client)
            if let result = viewModel.result {
                activityHistory.insert(result, at: 0)
            }
        } catch { viewModel.errorMessage = error.localizedDescription }
    }
}
