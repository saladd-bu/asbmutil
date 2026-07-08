import XCTest
@testable import ASBMUtilApp
import ASBMUtilCore

/// Guards the dashboard aggregation over the streamed device set. Per-server counts come
/// from a separate relationship fetch (the org-devices list omits the assigned server),
/// so they're supplied to `DashboardStats` as an explicit `serverCounts` map here.
final class DeviceAggregationTests: XCTestCase {

    /// Builds a DeviceAttributes via JSON so the real Decodable path is exercised and we
    /// don't have to spell out every optional field.
    private func device(
        serial: String,
        status: String? = nil,
        order: String? = nil,
        family: String? = nil
    ) -> DeviceAttributes {
        var obj: [String: Any] = ["serialNumber": serial]
        if let status { obj["status"] = status }
        if let order { obj["orderNumber"] = order }
        if let family { obj["productFamily"] = family }
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return try! JSONDecoder().decode(DeviceAttributes.self, from: data)
    }

    func testDashboardStatsSummary() {
        let devices = [
            device(serial: "A", status: "ASSIGNED", order: "O1", family: "iPad"),
            device(serial: "B", status: "ASSIGNED", order: "O1", family: "iPad"),
            device(serial: "C", status: "UNASSIGNED", order: "O2", family: "iPhone"),
        ]
        let servers = [
            MdmServerWithId(id: "srv1", serverName: "Server One", serverType: nil,
                            createdDateTime: nil, updatedDateTime: nil)
        ]
        // Counts as they'd arrive from the per-server relationship fetch.
        let serverCounts = ["srv1": 2]

        let stats = DashboardStats(devices: devices, servers: servers, serverCounts: serverCounts)

        XCTAssertEqual(stats.total, 3)
        XCTAssertEqual(stats.assigned, 2)
        XCTAssertEqual(stats.unassigned, 1)
        XCTAssertEqual(stats.uniqueOrders, 2)
        XCTAssertEqual(stats.serversInUse, 1)

        let srvBin = stats.serverBins.first { $0.idKey == "srv1" }
        XCTAssertEqual(srvBin?.count, 2)
        XCTAssertEqual(srvBin?.label, "Server One")
    }

    /// Servers with a zero count are filtered out of the bins (and serversInUse).
    func testDashboardStatsExcludesZeroCountServers() {
        let devices = [device(serial: "A", status: "UNASSIGNED")]
        let servers = [
            MdmServerWithId(id: "srv1", serverName: "Empty", serverType: nil,
                            createdDateTime: nil, updatedDateTime: nil)
        ]
        let stats = DashboardStats(devices: devices, servers: servers, serverCounts: ["srv1": 0])

        XCTAssertEqual(stats.serversInUse, 0)
        XCTAssertTrue(stats.serverBins.isEmpty)
    }
}
