import XCTest
@testable import LobsDashboard

final class StoreEncodingTests: XCTestCase {

    func testEncodeToPythonJSON_ConvertsColonSpace() throws {
        let store = LobsControlStore(repoRoot: URL(fileURLWithPath: "/tmp/test"))
        let task = TestFixtures.makeTask()

        let data = try store.encodeToPythonJSON(task)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should use Python format ": " not Swift format " : "
        XCTAssertTrue(jsonString.contains("\": \""))
        XCTAssertFalse(jsonString.contains("\" : \""))
    }

    func testEncodeToPythonJSON_PrettyPrinted() throws {
        let store = LobsControlStore(repoRoot: URL(fileURLWithPath: "/tmp/test"))
        let task = TestFixtures.makeTask()

        let data = try store.encodeToPythonJSON(task)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should be pretty-printed (contains newlines)
        XCTAssertTrue(jsonString.contains("\n"))
    }

    func testEncodeToPythonJSON_SortedKeys() throws {
        let store = LobsControlStore(repoRoot: URL(fileURLWithPath: "/tmp/test"))
        let task = TestFixtures.makeTask()

        let data = try store.encodeToPythonJSON(task)
        let jsonString = String(data: data, encoding: .utf8)!

        // Keys should be sorted alphabetically
        let idIndex = jsonString.range(of: "\"id\"")?.lowerBound
        let titleIndex = jsonString.range(of: "\"title\"")?.lowerBound

        XCTAssertNotNil(idIndex)
        XCTAssertNotNil(titleIndex)
        // "id" should come before "title" alphabetically
        XCTAssertLessThan(idIndex!, titleIndex!)
    }
}
