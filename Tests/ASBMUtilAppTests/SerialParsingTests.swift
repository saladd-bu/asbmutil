import XCTest
import ASBMUtilCore

/// The GUI fields and the CLI `--serials` option all funnel through
/// `CSVParser.parseSerialTokens`, so a person can separate serials with commas,
/// spaces, or newlines interchangeably. These guard that contract.
final class SerialParsingTests: XCTestCase {

    func testCommaSeparated() {
        XCTAssertEqual(CSVParser.parseSerialTokens("A1,B2,C3"), ["A1", "B2", "C3"])
    }

    func testWhitespaceAndNewlineSeparated() {
        XCTAssertEqual(CSVParser.parseSerialTokens("A1 B2\tC3"), ["A1", "B2", "C3"])
        XCTAssertEqual(CSVParser.parseSerialTokens("A1\nB2\nC3"), ["A1", "B2", "C3"])
    }

    func testMixedDelimiters() {
        XCTAssertEqual(CSVParser.parseSerialTokens("A1, B2\nC3\t,D4"), ["A1", "B2", "C3", "D4"])
    }

    func testTrailingAndRepeatedDelimitersAndEmpties() {
        XCTAssertEqual(CSVParser.parseSerialTokens("A1,,B2, ,\nC3,"), ["A1", "B2", "C3"])
        XCTAssertEqual(CSVParser.parseSerialTokens(""), [])
        XCTAssertEqual(CSVParser.parseSerialTokens("   \n\t "), [])
    }

    func testPreservesOrderAndDuplicates() {
        XCTAssertEqual(CSVParser.parseSerialTokens("A1 A1 B2"), ["A1", "A1", "B2"])
    }
}

/// `ActivityDetails.withStatus` is how a polled terminal status is propagated back
/// onto the submit-time activity object (whose status was frozen at "PENDING").
final class ActivityDetailsTests: XCTestCase {

    private func sample(status: String) -> ActivityDetails {
        ActivityDetails(
            id: "act-1", activityType: "UNASSIGN_DEVICES", status: status,
            createdDateTime: "2026-01-01T00:00:00Z", updatedDateTime: "2026-01-01T00:00:00Z",
            deviceCount: 2, deviceSerials: ["A1", "B2"],
            mdmServerName: nil, mdmServerType: nil, mdmServerId: nil
        )
    }

    func testWithStatusReplacesOnlyStatus() {
        let original = sample(status: "PENDING")
        let updated = original.withStatus("COMPLETED")

        XCTAssertEqual(updated.status, "COMPLETED")
        // Everything else is carried over unchanged.
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.activityType, original.activityType)
        XCTAssertEqual(updated.deviceSerials, original.deviceSerials)
        XCTAssertNil(updated.mdmServerId)
        // Original is untouched (value type).
        XCTAssertEqual(original.status, "PENDING")
    }
}
