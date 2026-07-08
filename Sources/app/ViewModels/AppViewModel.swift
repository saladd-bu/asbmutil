import Foundation
import ASBMUtilCore

@Observable
@MainActor
final class AppViewModel {
    // Profile management
    private(set) var profiles: [ProfileInfo] = []
    var activeProfile: String = "default"
    private(set) var isAuthenticated = false

    // Shared API client (recreated on profile switch)
    private(set) var apiClient: APIClient?

    // Connection status
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var connectionError: String?

    // Shared device + server caches (Dashboard and Devices both read from these)
    var devices: [DeviceAttributes] = []
    var mdmServers: [MdmServerWithId] = []
    var serverDeviceCounts: [String: Int] = [:]
    var isLoadingServerCounts = false
    var deviceLoadError: String?
    var devicesLastLoaded: Date?

    // Drives the progress indicator and the pause/resume controls. The device set
    // streams in page-by-page, so views render whatever has arrived so far.
    var deviceLoadState: DeviceLoadState = .idle

    // Memoized dashboard aggregation, recomputed off the main actor as pages arrive
    // (debounced) so DashboardView never re-derives it during a render pass.
    var dashboardStats: DashboardStats = .empty

    // Shared device filter state — survives navigation between sections
    let deviceFilters = DeviceFilters()

    /// Convenience for views that just want to know whether a load is actively running.
    var isLoadingDevices: Bool { deviceLoadState == .loading }

    // The streaming load lives on the view model, not a view's `.task`, so it keeps
    // running when the user tabs between Dashboard and Devices and is only stopped by
    // an explicit pause, refresh, or profile switch.
    private var loadTask: Task<Void, Never>?
    // Cursor for the next page; retained across a pause so resume continues in place.
    private var resumeCursor: String?
    // Debounces off-main-thread dashboard recomputation while pages stream in.
    private var statsRecomputeTask: Task<Void, Never>?
    // The `/v1/orgDevices` list doesn't carry the assigned MDM server, so per-server
    // counts come from a separate relationship fetch fanned out per server. Runs in the
    // background alongside the device stream and is cancelable on refresh/profile switch.
    private var serverCountsTask: Task<Void, Never>?

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    enum DeviceLoadState: Equatable {
        case idle
        case loading
        case paused
        case complete
        case failed(String)
    }

    init() {
        loadProfiles()
    }

    func loadProfiles() {
        profiles = Keychain.listProfiles()
        activeProfile = Keychain.getCurrentProfile()
    }

    func switchProfile(_ name: String) async {
        loadTask?.cancel()
        loadTask = nil
        serverCountsTask?.cancel()
        serverCountsTask = nil
        statsRecomputeTask?.cancel()
        statsRecomputeTask = nil

        activeProfile = name
        _ = Keychain.setCurrentProfile(name)
        apiClient = nil
        connectionState = .disconnected
        isAuthenticated = false
        connectionError = nil
        devices = []
        mdmServers = []
        serverDeviceCounts = [:]
        resumeCursor = nil
        deviceLoadError = nil
        devicesLastLoaded = nil
        deviceLoadState = .idle
        dashboardStats = .empty
        deviceFilters.clearAll()
    }

    func connect() async {
        connectionState = .connecting
        connectionError = nil

        do {
            let credentials = try Creds.load(profileName: activeProfile)
            let client = try await APIClient(credentials: credentials, profileName: activeProfile)
            apiClient = client
            connectionState = .connected
            isAuthenticated = true
        } catch {
            connectionState = .error(error.localizedDescription)
            connectionError = error.localizedDescription
            isAuthenticated = false
            apiClient = nil
        }
    }

    func disconnect() {
        apiClient = nil
        connectionState = .disconnected
        isAuthenticated = false
        connectionError = nil
    }

    /// Ensure we have an active API client, connecting if needed
    func ensureConnected() async throws -> APIClient {
        if let client = apiClient {
            return client
        }
        await connect()
        guard let client = apiClient else {
            throw RuntimeError(connectionError ?? "Failed to connect")
        }
        return client
    }

    // MARK: - Device + Server loading

    /// Starts an initial load only if one isn't already running/paused/complete.
    /// Idempotent and safe to call from multiple views' `.task`, so tabbing between
    /// Dashboard and Devices never spawns a second load or restarts the current one.
    func startLoadIfNeeded() {
        switch deviceLoadState {
        case .idle, .failed:
            beginLoad(reset: true)
        case .loading, .paused, .complete:
            break
        }
    }

    /// Discards any partial data and reloads from the first page.
    func refreshDevices() {
        beginLoad(reset: true)
    }

    /// Pauses the in-flight load, keeping the devices loaded so far and the cursor
    /// needed to continue. No-op unless a load is actively running.
    func pauseLoad() {
        guard deviceLoadState == .loading else { return }
        loadTask?.cancel()
        // .paused is set by runLoad's cancellation handling once the task unwinds.
    }

    /// Resumes a paused load from the last cursor without re-fetching earlier pages.
    func resumeLoad() {
        guard deviceLoadState == .paused else { return }
        beginLoad(reset: false)
    }

    private func beginLoad(reset: Bool) {
        loadTask?.cancel()
        serverCountsTask?.cancel()
        if reset {
            devices = []
            serverDeviceCounts = [:]
            isLoadingServerCounts = false
            resumeCursor = nil
            dashboardStats = .empty
            deviceFilters.clearAll()
        }
        deviceLoadError = nil
        deviceLoadState = .loading

        loadTask = Task { [weak self] in
            await self?.runLoad()
        }
    }

    private func runLoad() async {
        do {
            let client = try await ensureConnected()

            // Server list is a single cheap request; fetch it once so per-server
            // counts can be labeled with names.
            if mdmServers.isEmpty {
                mdmServers = try await client.listMdmServers()
            }

            // Kick off per-server counts in the background so they resolve alongside the
            // device stream rather than after it. Skipped on resume if already loaded.
            if serverDeviceCounts.isEmpty {
                startServerCountsLoad(client: client)
            }

            try await client.streamDevices(startCursor: resumeCursor, devicesPerPage: 1000) { [weak self] page, nextCursor, _, _ in
                await self?.appendPage(page, nextCursor: nextCursor)
            }

            // Completed the final page.
            resumeCursor = nil
            deviceLoadState = .complete
            devicesLastLoaded = Date()
            deviceFilters.buildFromDevices(devices)
            recomputeDashboardStats(debounced: false)
        } catch {
            // A pause (or profile switch) cancels the task; URLSession reports that as
            // URLError.cancelled rather than CancellationError, so key off isCancelled
            // to distinguish an intentional stop from a real failure.
            if Task.isCancelled {
                deviceLoadState = .paused
            } else {
                deviceLoadError = error.localizedDescription
                deviceLoadState = .failed(error.localizedDescription)
            }
        }
    }

    /// Appends a freshly-fetched page on the main actor and advances derived state.
    private func appendPage(_ page: [DeviceAttributes], nextCursor: String?) {
        // Populate the dashboard immediately on the first batch so cards fill in as soon
        // as data appears; debounce afterwards so charts don't thrash on every page.
        let isFirstBatch = dashboardStats.total == 0
        devices.append(contentsOf: page)
        resumeCursor = nextCursor
        recomputeDashboardStats(debounced: !isFirstBatch)
    }

    // MARK: - Per-server counts

    /// Fans out one `listMdmServerDevices` request per MDM server to count assigned
    /// devices, since the org-devices list doesn't include the assigned server. Runs off
    /// the main thread and never blocks device streaming; a server whose count can't be
    /// read is simply omitted. Cancelable via `serverCountsTask`.
    private func startServerCountsLoad(client: APIClient) {
        serverCountsTask?.cancel()
        let servers = mdmServers
        guard !servers.isEmpty else { return }
        isLoadingServerCounts = true

        serverCountsTask = Task { [weak self] in
            let counts = await withTaskGroup(of: (String, Int)?.self) { group -> [String: Int] in
                for server in servers {
                    let id = server.id
                    group.addTask {
                        do {
                            let serials = try await client.listMdmServerDevices(serverId: id)
                            return (id, serials.count)
                        } catch {
                            return nil
                        }
                    }
                }
                var out: [String: Int] = [:]
                for await result in group {
                    if let (id, count) = result { out[id] = count }
                }
                return out
            }
            self?.applyServerCounts(counts)
        }
    }

    /// Publishes fanned-out counts on the main actor and refreshes the dashboard. Drops
    /// the result if the task was cancelled (refresh/profile switch) to avoid clobbering.
    private func applyServerCounts(_ counts: [String: Int]) {
        guard !Task.isCancelled else { return }
        serverDeviceCounts = counts
        isLoadingServerCounts = false
        recomputeDashboardStats(debounced: false)
    }

    /// Recomputes `dashboardStats` off the main actor. While streaming we debounce so
    /// charts don't thrash on every page; the completion path forces an immediate,
    /// authoritative recompute.
    private func recomputeDashboardStats(debounced: Bool) {
        statsRecomputeTask?.cancel()
        guard debounced else {
            computeDashboardStatsNow()
            return
        }
        statsRecomputeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000) // ~0.4s
            guard !Task.isCancelled else { return }
            self?.computeDashboardStatsNow()
        }
    }

    private func computeDashboardStatsNow() {
        let devs = devices
        let servers = mdmServers
        let counts = serverDeviceCounts
        Task.detached(priority: .userInitiated) { [weak self] in
            let stats = DashboardStats(devices: devs, servers: servers, serverCounts: counts)
            await MainActor.run { self?.dashboardStats = stats }
        }
    }
}
