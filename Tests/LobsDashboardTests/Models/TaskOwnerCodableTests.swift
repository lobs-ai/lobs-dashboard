import XCTest
@testable import LobsDashboard

final class TaskOwnerCodableTests: XCTestCase {

    func testEncodeDecodeLobs() throws {
        let owner = TaskOwner.lobs
        let encoded = try JSONEncoder().encode(owner)
        let decoded = try JSONDecoder().decode(TaskOwner.self, from: encoded)
        XCTAssertEqual(decoded, .lobs)
    }

    func testEncodeDecodeRafe() throws {
        let owner = TaskOwner.rafe
        let encoded = try JSONEncoder().encode(owner)
        let decoded = try JSONDecoder().decode(TaskOwner.self, from: encoded)
        XCTAssertEqual(decoded, .rafe)
    }

    func testEncodeDecodeOther() throws {
        let owner = TaskOwner.other("alice")
        let encoded = try JSONEncoder().encode(owner)
        let decoded = try JSONDecoder().decode(TaskOwner.self, from: encoded)
        XCTAssertEqual(decoded, .other("alice"))
    }

    func testDecodeUnknownValueFallsBackToOther() throws {
        let json = "\"unknown_user\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TaskOwner.self, from: json)
        XCTAssertEqual(decoded, .other("unknown_user"))
    }
}
