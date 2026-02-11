import XCTest
@testable import LobsDashboard

final class TaskStatusCodableTests: XCTestCase {

    func testEncodeDecodeInbox() throws {
        let status = TaskStatus.inbox
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(TaskStatus.self, from: encoded)
        XCTAssertEqual(decoded, .inbox)
        XCTAssertEqual(decoded.rawValue, "inbox")
    }

    func testEncodeDecodeActive() throws {
        let status = TaskStatus.active
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(TaskStatus.self, from: encoded)
        XCTAssertEqual(decoded, .active)
    }

    func testEncodeDecodeWaitingOn() throws {
        let status = TaskStatus.waitingOn
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(TaskStatus.self, from: encoded)
        XCTAssertEqual(decoded, .waitingOn)
        // Verify snake_case encoding
        let jsonString = String(data: encoded, encoding: .utf8)
        XCTAssertTrue(jsonString?.contains("waiting_on") == true)
    }

    func testEncodeDecodeOther() throws {
        let status = TaskStatus.other("custom_status")
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(TaskStatus.self, from: encoded)
        XCTAssertEqual(decoded, .other("custom_status"))
        XCTAssertEqual(decoded.rawValue, "custom_status")
    }

    func testDecodeUnknownValueFallsBackToOther() throws {
        let json = "\"unknown_status\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TaskStatus.self, from: json)
        XCTAssertEqual(decoded, .other("unknown_status"))
    }
}
