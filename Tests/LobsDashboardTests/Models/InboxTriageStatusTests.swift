import XCTest
@testable import LobsDashboard

final class InboxTriageStatusTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(InboxTriageStatus.needsResponse.displayName, "Needs Response")
        XCTAssertEqual(InboxTriageStatus.pending.displayName, "Pending")
        XCTAssertEqual(InboxTriageStatus.resolved.displayName, "Resolved")
    }

    func testIconNames() {
        XCTAssertEqual(InboxTriageStatus.needsResponse.iconName, "exclamationmark.bubble.fill")
        XCTAssertEqual(InboxTriageStatus.pending.iconName, "clock.fill")
        XCTAssertEqual(InboxTriageStatus.resolved.iconName, "checkmark.circle.fill")
    }

    func testColors() {
        XCTAssertEqual(InboxTriageStatus.needsResponse.color, "orange")
        XCTAssertEqual(InboxTriageStatus.pending.color, "blue")
        XCTAssertEqual(InboxTriageStatus.resolved.color, "green")
    }

    func testRawValues() {
        XCTAssertEqual(InboxTriageStatus.needsResponse.rawValue, "needs_response")
        XCTAssertEqual(InboxTriageStatus.pending.rawValue, "pending")
        XCTAssertEqual(InboxTriageStatus.resolved.rawValue, "resolved")
    }
}
