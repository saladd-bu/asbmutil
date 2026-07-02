import XCTest
@testable import ASBMUtilApp

/// The palette is now native system colors (Apple-managed contrast), so there's
/// no hand-authored hex to assert ratios against. What still needs guarding is
/// the status vocabulary: raw API values must bucket and title-case correctly.
final class StatusFormattingTests: XCTestCase {

    func testDisplayLabelTitleCasesRawStatus() {
        XCTAssertEqual(StatusStyle.displayLabel("IN_PROGRESS"), "In Progress")
        XCTAssertEqual(StatusStyle.displayLabel("ASSIGNED"), "Assigned")
        XCTAssertEqual(StatusStyle.displayLabel("TIMEOUT"), "Timeout")
        XCTAssertEqual(StatusStyle.displayLabel("UNKNOWN_FUTURE_STATE"), "Unknown Future State")
        XCTAssertEqual(StatusStyle.displayLabel(""), "Unknown")
    }

    func testStatusBucketing() {
        XCTAssertEqual(StatusKind(apiStatus: "ASSIGNED"), .success)
        XCTAssertEqual(StatusKind(apiStatus: "connected"), .success)   // case-insensitive
        XCTAssertEqual(StatusKind(apiStatus: "UNASSIGNED"), .warning)
        XCTAssertEqual(StatusKind(apiStatus: "IN_PROGRESS"), .warning)
        XCTAssertEqual(StatusKind(apiStatus: "FAILED"), .failure)
        XCTAssertEqual(StatusKind(apiStatus: "TIMEOUT"), .timeout)
        XCTAssertEqual(StatusKind(apiStatus: "SOMETHING_ELSE"), .neutral)
    }
}
