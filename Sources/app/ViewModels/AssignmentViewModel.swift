import Foundation
import ASBMUtilCore

enum AssignmentMode: String, CaseIterable {
    case assign = "Assign"
    case unassign = "Unassign"
}

@Observable
@MainActor
final class AssignmentViewModel {
    var mode: AssignmentMode = .assign
    var selectedMdmName = ""
    var serialInput = ""
    var importedSerials: [String] = []
    var isExecuting = false
    var result: ActivityDetails?
    var errorMessage: String?
    var servers: [MdmServerWithId] = []

    /// Activities submitted during this session, newest first. Owned here (not the view)
    /// so it survives tab switches and so a single update path keeps the Result box and
    /// the Session Activity row in sync when confirmation resolves the terminal status.
    var activityHistory: [ActivityDetails] = []

    /// Skip the pre-flight existence check and submit serials as-is.
    var skipVerify = false
    /// Serials Apple reported as not found (HTTP 404) during the last run — excluded from submission.
    var notFoundSerials: [String] = []
    /// Serials whose existence couldn't be determined during the last run — excluded from submission.
    var erroredSerials: [String] = []
    /// Unassign only: serials that were already not assigned to any server, so nothing was submitted.
    var alreadyUnassigned: [String] = []
    /// A one-line summary shown after a multi-server unassign (which produces several activities).
    var submissionSummary: String?

    /// After submitting, poll the activity and re-query each device to confirm the end state.
    var confirmAfterSubmit = false
    /// Whether a confirmation pass ran and produced results to show.
    var didConfirm = false
    /// Human-readable terminal status of the confirmed activity (e.g. COMPLETED, TIMEOUT).
    var confirmStatus: String?
    /// Count of devices confirmed in the expected end state.
    var confirmedCount = 0
    /// Serials that settled in a different state than intended.
    var confirmMismatched: [String] = []
    /// Serials whose final assignment couldn't be read.
    var confirmErrored: [String] = []

    var serialNumbers: [String] {
        if !importedSerials.isEmpty {
            return importedSerials
        }
        return CSVParser.parseSerialTokens(serialInput)
    }

    /// Assign needs a target server; unassign does not (it removes each device from
    /// wherever it currently is), so the server picker is hidden in unassign mode.
    var requiresServer: Bool { mode == .assign }

    var canExecute: Bool {
        guard !serialNumbers.isEmpty, !isExecuting else { return false }
        return requiresServer ? !selectedMdmName.isEmpty : true
    }

    func loadServers(client: APIClient) async {
        do {
            servers = try await client.listMdmServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func execute(client: APIClient) async {
        guard canExecute else { return }
        isExecuting = true
        errorMessage = nil
        result = nil
        notFoundSerials = []
        erroredSerials = []
        alreadyUnassigned = []
        submissionSummary = nil
        didConfirm = false
        confirmStatus = nil
        confirmedCount = 0
        confirmMismatched = []
        confirmErrored = []

        do {
            // Pre-flight each serial unless the user opted out. Apple's activities endpoint
            // reports success even for serials that don't exist (e.g. not yet registered by
            // the reseller), so we filter those out and surface them for review.
            let toSubmit: [String]
            if skipVerify {
                toSubmit = serialNumbers
            } else {
                let verification = await client.verifyDevices(serials: serialNumbers)
                notFoundSerials = verification.notFound
                erroredSerials = verification.errored.map { "\($0.serial): \($0.message)" }
                guard !verification.found.isEmpty else {
                    errorMessage = "No valid devices: all \(serialNumbers.count) serial(s) were not found or could not be verified."
                    isExecuting = false
                    return
                }
                toSubmit = verification.found
            }

            if mode == .assign {
                try await runAssign(serials: toSubmit, client: client)
            } else {
                try await runUnassign(serials: toSubmit, client: client)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isExecuting = false
    }

    private func runAssign(serials: [String], client: APIClient) async throws {
        let serviceId = try await client.getMdmServerIdByName(selectedMdmName)
        let activity = try await client.createDeviceActivity(
            activityType: "ASSIGN_DEVICES", serials: serials, serviceId: serviceId
        )
        result = activity
        activityHistory.insert(activity, at: 0)

        if confirmAfterSubmit {
            await confirm(activities: [activity], serials: serials,
                          expected: .assigned(serverId: serviceId), client: client)
        }
    }

    private func runUnassign(serials: [String], client: APIClient) async throws {
        // Apple requires a server target on UNASSIGN, so we look up each device's current
        // server and submit one activity per server — the user never has to pick one.
        let outcome = try await client.unassignFromCurrentServer(serials: serials)
        alreadyUnassigned = outcome.alreadyUnassigned
        notFoundSerials += outcome.notFound
        erroredSerials += outcome.errored.map { "\($0.serial): \($0.message)" }

        for activity in outcome.activities.reversed() {
            activityHistory.insert(activity, at: 0)
        }
        // One activity: show it in the Result box. Several (devices across servers): show
        // a summary instead and let each appear in Session Activity.
        result = outcome.activities.count == 1 ? outcome.activities.first : nil
        if outcome.activities.count > 1 {
            let devices = outcome.submittedSerials.count
            submissionSummary = "Unassigned \(devices) device(s) across \(outcome.activities.count) servers."
        }

        if outcome.activities.isEmpty {
            errorMessage = "None of the \(serials.count) device(s) are currently assigned to a server."
            return
        }

        if confirmAfterSubmit {
            await confirm(activities: outcome.activities, serials: outcome.submittedSerials,
                          expected: .unassignedAny, client: client)
        }
    }

    /// Poll every submitted activity to a terminal state, propagate the terminal status
    /// back onto the Result box + Session Activity rows, then reconcile each device's
    /// actual end state against `expected`.
    private func confirm(activities: [ActivityDetails], serials: [String],
                         expected: AssignmentExpectation, client: APIClient) async {
        var sawTimeout = false
        for activity in activities {
            let status = (try? await client.waitForActivityTerminal(
                id: activity.id, intervalSeconds: 10, timeoutSeconds: 240
            )) ?? "TIMEOUT"
            if status == "TIMEOUT" {
                sawTimeout = true
            } else {
                updateActivityStatus(id: activity.id, to: status)
            }
        }
        confirmStatus = sawTimeout ? "TIMEOUT" : "COMPLETED"

        if !sawTimeout {
            let reconciliation = await client.confirmAssignment(serials: serials, expected: expected)
            confirmedCount = reconciliation.asExpected.count
            confirmMismatched = reconciliation.mismatched.map { "\($0.serial): now \($0.assignedTo.map { "on \($0)" } ?? "unassigned")" }
            confirmErrored = reconciliation.errored.map { "\($0.serial): \($0.message)" }
        }
        didConfirm = true
    }

    /// Replace an activity's status in both `result` and `activityHistory` so every
    /// display of that activity reflects the same (terminal) status.
    private func updateActivityStatus(id: String, to newStatus: String) {
        if let result, result.id == id {
            self.result = result.withStatus(newStatus)
        }
        if let idx = activityHistory.firstIndex(where: { $0.id == id }) {
            activityHistory[idx] = activityHistory[idx].withStatus(newStatus)
        }
    }

    func reset() {
        serialInput = ""
        importedSerials.removeAll()
        result = nil
        errorMessage = nil
        notFoundSerials = []
        erroredSerials = []
        alreadyUnassigned = []
        submissionSummary = nil
        didConfirm = false
        confirmStatus = nil
        confirmedCount = 0
        confirmMismatched = []
        confirmErrored = []
    }

    /// Parse a CSV without committing it, for a preview step. Returns nil (and sets
    /// `errorMessage`) if the file can't be read or contains no serials.
    func readCSV(from url: URL) -> [String]? {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access file"
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            return try CSVParser.readSerials(from: url)
        } catch {
            errorMessage = "CSV import failed: \(error.localizedDescription)"
            return nil
        }
    }
}
