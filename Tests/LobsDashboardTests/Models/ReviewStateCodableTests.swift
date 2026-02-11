import XCTest
@testable import LobsDashboard

final class ReviewStateCodableTests: XCTestCase {

    func testEncodeDecodePending() throws {
        let state = ReviewState.pending
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReviewState.self, from: encoded)
        XCTAssertEqual(decoded, .pending)
    }

    func testEncodeDecodeApproved() throws {
        let state = ReviewState.approved
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReviewState.self, from: encoded)
        XCTAssertEqual(decoded, .approved)
    }

    func testEncodeDecodeChangesRequested() throws {
        let state = ReviewState.changesRequested
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReviewState.self, from: encoded)
        XCTAssertEqual(decoded, .changesRequested)
        let jsonString = String(data: encoded, encoding: .utf8)
        XCTAssertTrue(jsonString?.contains("changes_requested") == true)
    }

    func testEncodeDecodeOther() throws {
        let state = ReviewState.other("deferred")
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReviewState.self, from: encoded)
        XCTAssertEqual(decoded, .other("deferred"))
    }

    func testDecodeUnknownValueFallsBackToOther() throws {
        let json = "\"custom_review\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ReviewState.self, from: json)
        XCTAssertEqual(decoded, .other("custom_review"))
    }
}
