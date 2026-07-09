import SwiftUI
import ASBMUtilCore

struct BatchStatusView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @FocusState private var idFocused: Bool

    // Owned by AppViewModel so the activity id, status, and poll log survive tab switches.
    private var viewModel: BatchStatusViewModel { appViewModel.batchStatusModel }

    var body: some View {
        @Bindable var viewModel = appViewModel.batchStatusModel

        VStack(alignment: .leading, spacing: 0) {
            // Input area
            LabeledSection("Activity") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    TextField("Activity ID", text: $viewModel.activityId)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .focused($idFocused)

                    HStack {
                        Button("Check Status") {
                            Task { await checkOnce() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canCheck)

                        if viewModel.isPolling {
                            Button("Stop Polling") { viewModel.stopPolling() }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Start Polling") {
                                Task { await startPolling() }
                            }
                            .disabled(!viewModel.canCheck)
                        }

                        Spacer()

                        HStack(spacing: Spacing.md) {
                            LabeledContent("Interval") {
                                Stepper("\(viewModel.pollInterval)s", value: $viewModel.pollInterval, in: 1...120)
                            }
                            LabeledContent("Timeout") {
                                Stepper("\(viewModel.pollTimeout)s", value: $viewModel.pollTimeout, in: 10...3600, step: 30)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .padding()

            if !viewModel.status.isEmpty {
                LabeledContent("Status") {
                    StatusBadge(status: viewModel.status)
                }
                .padding(.horizontal)
            }

            if viewModel.isChecking {
                ProgressView().controlSize(.small).padding(.horizontal)
            }

            if let error = viewModel.errorMessage {
                InlineHint(.danger, error, isLive: false)
                    .padding(.horizontal)
            }

            // Poll log / empty state
            if !viewModel.pollLog.isEmpty {
                Divider().padding(.top, Spacing.sm)
                SectionHeader("Poll Log")
                    .padding(.horizontal)
                    .padding(.top, Spacing.sm)

                List(viewModel.pollLog) { entry in
                    HStack {
                        Text(entry.timestamp, style: .time)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        StatusBadge(status: entry.status)
                    }
                }
            } else if viewModel.status.isEmpty {
                ContentUnavailableView("No Status Checked", systemImage: "clock.arrow.circlepath",
                                       description: Text("Enter an activity ID above to check its status once, or poll until it finishes."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .navigationTitle("Batch Status")
        .onAppear { if viewModel.status.isEmpty && !viewModel.isPolling { idFocused = true } }
    }

    private func checkOnce() async {
        do {
            let client = try await appViewModel.ensureConnected()
            await appViewModel.batchStatusModel.checkOnce(client: client)
        } catch {
            appViewModel.batchStatusModel.errorMessage = error.localizedDescription
        }
    }

    private func startPolling() async {
        do {
            let client = try await appViewModel.ensureConnected()
            appViewModel.batchStatusModel.startPolling(client: client)
        } catch {
            appViewModel.batchStatusModel.errorMessage = error.localizedDescription
        }
    }
}
