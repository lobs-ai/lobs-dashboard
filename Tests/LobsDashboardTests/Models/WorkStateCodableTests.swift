import XCTest
@testable import LobsDashboard

final class WorkStateCodableTests: XCTestCase {

    func testEncodeDecodeNotStarted() throws {
        let state = WorkState.notStarted
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkState.self, from: encoded)
        XCTAssertEqual(decoded, .notStarted)
        // Verify snake_case
        let jsonString = String(data: encoded, encoding: .utf8)
        XCTAssertTrue(jsonString?.contains("not_started") == true)
    }

    func testEncodeDecodeInProgress() throws {
        let state = WorkState.inProgress
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkState.self, from: encoded)
        XCTAssertEqual(decoded, .inProgress)
        let jsonString = String(data: encoded, encoding: .utf8)
        XCTAssertTrue(jsonString?.contains("in_progress") == true)
    }

    func testEncodeDecodeBlocked() throws {
        let state = WorkState.blocked
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkState.self, from: encoded)
        XCTAssertEqual(decoded, .blocked)
    }

    func testEncodeDecodeOther() throws {
        let state = WorkState.other("paused")
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkState.self, from: encoded)
        XCTAssertEqual(decoded, .other("paused"))
    }

    func testDecodeUnknownValueFallsBackToOther() throws {
        let json = "\"custom_state\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkState.self, from: json)
        XCTAssertEqual(decoded, .other("custom_state"))
    }
}
