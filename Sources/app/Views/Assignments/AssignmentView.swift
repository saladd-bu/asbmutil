import SwiftUI
import UniformTypeIdentifiers
import ASBMUtilCore

struct AssignmentView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var showFilePicker = false
    @State private var showActivity = true
    @State private var pendingImport: [String] = []
    @State private var showImportPreview = false
    @FocusState private var inputFocused: Bool

    // Owned by AppViewModel so input, results, and session activity survive tab switches.
    private var viewModel: AssignmentViewModel { appViewModel.assignmentModel }

    private let resultAnchor = "result"

    var body: some View {
        @Bindable var viewModel = appViewModel.assignmentModel

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(alignment: .top, spacing: Spacing.lg) {
                        LabeledSection("Operation") {
                            Picker("Mode", selection: $viewModel.mode) {
                                ForEach(AssignmentMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }

                        if viewModel.requiresServer {
                            LabeledSection("Server") { serverPicker }
                        }
                    }

                    LabeledSection("Device Serials") { serialInputSection }

                    executeSection
                        .id(resultAnchor)

                    sessionActivitySection
                }
                .padding()
            }
            .onChange(of: viewModel.result?.id) { _, newValue in
                guard newValue != nil else { return }
                withAnimation { proxy.scrollTo(resultAnchor, anchor: .top) }
            }
            .onChange(of: viewModel.didConfirm) { _, confirmed in
                if confirmed { withAnimation { proxy.scrollTo(resultAnchor, anchor: .top) } }
            }
        }
        .navigationTitle("Assignments")
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first,
               let parsed = appViewModel.assignmentModel.readCSV(from: url) {
                pendingImport = parsed
                showImportPreview = true
            }
        }
        .sheet(isPresented: $showImportPreview) {
            CSVImportView(serials: pendingImport) { confirmed in
                appViewModel.assignmentModel.importedSerials = confirmed
            }
        }
        .task {
            if viewModel.servers.isEmpty { await loadServers() }
        }
    }

    // MARK: - Server picker

    @ViewBuilder
    private var serverPicker: some View {
        @Bindable var viewModel = appViewModel.assignmentModel
        if viewModel.servers.isEmpty {
            HStack {
                Text("No servers loaded").foregroundStyle(.secondary)
                Spacer()
                Button("Load") { Task { await loadServers() } }
            }
        } else {
            Picker("Server", selection: $viewModel.selectedMdmName) {
                Text("Select a server…").tag("")
                ForEach(viewModel.servers, id: \.id) { s in
                    Text(s.serverName ?? s.id).tag(s.serverName ?? "")
                }
            }
            .labelsHidden()
        }
    }

    // MARK: - Serial input

    private var serialInputSection: some View {
        @Bindable var viewModel = appViewModel.assignmentModel
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SerialInputField(
                text: $viewModel.serialInput,
                isDisabled: !viewModel.importedSerials.isEmpty,
                isFocused: $inputFocused
            )
            .accessibilityLabel("Device serial numbers")
            .accessibilityHint("Enter serial numbers separated by commas, spaces, or new lines. Press Command-Return to submit.")

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
                .help("After submitting, waits for the activity to finish and re-queries each device to confirm it actually reached the intended state. Slower, since it polls until the activity completes.")
        }
    }

    // MARK: - Execute / result / confirmation

    @ViewBuilder
    private var executeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Button(viewModel.mode == .assign ? "Assign Devices" : "Unassign Devices") {
                    Task { await execute() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .tint(viewModel.mode == .assign ? .blue : .orange)
                .disabled(!viewModel.canExecute)

                if viewModel.isExecuting { ProgressView().controlSize(.small) }
            }

            if let error = viewModel.errorMessage {
                InlineHint(.danger, error)
            }

            if !viewModel.notFoundSerials.isEmpty || !viewModel.erroredSerials.isEmpty {
                excludedBox
            }

            if let summary = viewModel.submissionSummary {
                InlineHint(.success, summary)
            }

            if !viewModel.alreadyUnassigned.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                        InlineHint(.info, "\(viewModel.alreadyUnassigned.count) device(s) already unassigned")
                        Text(viewModel.alreadyUnassigned.joined(separator: ", "))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let result = viewModel.result {
                LabeledSection("Result") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        infoRow("Activity ID", value: result.id, mono: true, copyable: true)
                        HStack(spacing: Spacing.sm) {
                            rowLabel("Status")
                            StatusBadge(status: result.status)
                            Spacer()
                        }
                        infoRow("Devices", value: "\(result.deviceCount)")
                    }
                }
            }

            if viewModel.didConfirm {
                LabeledSection("Confirmation") {
                    confirmationContent
                }
            }
        }
    }

    private var excludedBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                if !viewModel.notFoundSerials.isEmpty {
                    InlineHint(.warning, "\(viewModel.notFoundSerials.count) serial(s) not found, excluded")
                    Text(viewModel.notFoundSerials.joined(separator: ", "))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Not in School/Business Manager yet, or mistyped.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !viewModel.erroredSerials.isEmpty {
                    InlineHint(.warning, "\(viewModel.erroredSerials.count) serial(s) could not be verified, excluded")
                    Text(viewModel.erroredSerials.joined(separator: "\n"))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var confirmationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            if let status = viewModel.confirmStatus {
                infoRow("Activity", value: StatusStyle.displayLabel(status))
            }
            if viewModel.confirmStatus == "TIMEOUT" {
                InlineHint(.warning, "Activity didn't finish in time; end state not confirmed.")
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

    // MARK: - Row helpers

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .frame(width: 90, alignment: .leading)
    }

    /// A label→value row: secondary fixed-width label, primary value, with an optional
    /// copy icon beside the value.
    private func infoRow(_ label: String, value: String, mono: Bool = false, copyable: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            rowLabel(label)
            Text(value)
                .font(mono ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(label)")
            }
            Spacer()
        }
    }

    // MARK: - Session activity (collapsible)

    @ViewBuilder
    private var sessionActivitySection: some View {
        DisclosureGroup(isExpanded: $showActivity) {
            if viewModel.activityHistory.isEmpty {
                Text("Activities from this session will appear here.")
                    .foregroundStyle(.secondary).font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.activityHistory) { activity in
                        activityRow(activity)
                        if activity.id != viewModel.activityHistory.last?.id { Divider() }
                    }
                }
                .frame(maxHeight: 240)
            }
        } label: {
            HStack {
                SectionHeader("Session Activity")
                if !viewModel.activityHistory.isEmpty {
                    Text("\(viewModel.activityHistory.count)")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.sm).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }

    private func activityRow(_ activity: ActivityDetails) -> some View {
        let isUnassign = activity.activityType.contains("UNASSIGN")
        return HStack(spacing: 10) {
            Image(systemName: isUnassign ? "arrow.uturn.backward.square" : "arrow.right.square")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.deviceSerials.count == 1 ? activity.deviceSerials[0] : "Multiple")
                    .font(.callout).fontWeight(.medium)
                Text(activitySubtitle(activity))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: activity.status)
        }
        .padding(.vertical, Spacing.xs + 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUnassign ? "Unassign" : "Assign"), \(activity.deviceSerials.count == 1 ? activity.deviceSerials[0] : "\(activity.deviceCount) devices"), \(activitySubtitle(activity)), status \(StatusStyle.displayLabel(activity.status))")
    }

    /// "N Devices · Server" — or just the device count for a server-less unassign.
    private func activitySubtitle(_ a: ActivityDetails) -> String {
        let count = "\(a.deviceCount) Device\(a.deviceCount == 1 ? "" : "s")"
        if let server = a.mdmServerName ?? a.mdmServerId {
            return "\(count) \u{00B7} \(server)"
        }
        return count
    }

    // MARK: - Actions

    private func loadServers() async {
        do {
            let client = try await appViewModel.ensureConnected()
            await appViewModel.assignmentModel.loadServers(client: client)
        } catch { appViewModel.assignmentModel.errorMessage = error.localizedDescription }
    }

    private func execute() async {
        do {
            let client = try await appViewModel.ensureConnected()
            await appViewModel.assignmentModel.execute(client: client)
        } catch { appViewModel.assignmentModel.errorMessage = error.localizedDescription }
    }
}
