import XCTest
@testable import LobsDashboard

final class PaletteQueryTests: XCTestCase {

    func testEmptyQuery() {
        let query = PaletteQuery.parse("")
        XCTAssertEqual(query.searchText, "")
        XCTAssertEqual(query.searchTokens, [])
        XCTAssertNil(query.projectFilter)
    }

    func testSimpleQuery() {
        let query = PaletteQuery.parse("foo bar")
        XCTAssertEqual(query.searchText, "foo bar")
        XCTAssertEqual(query.searchTokens, ["foo", "bar"])
        XCTAssertNil(query.projectFilter)
    }

    func testProjectFilterWithIn() {
        let query = PaletteQuery.parse("foo in:dashboard")
        XCTAssertEqual(query.searchText, "foo")
        XCTAssertEqual(query.searchTokens, ["foo"])
        XCTAssertEqual(query.projectFilter, "dashboard")
    }

    func testProjectFilterWithProject() {
        let query = PaletteQuery.parse("bar project:lobs")
        XCTAssertEqual(query.searchText, "bar")
        XCTAssertEqual(query.searchTokens, ["bar"])
        XCTAssertEqual(query.projectFilter, "lobs")
    }

    func testProjectFilterCaseInsensitive() {
        let query1 = PaletteQuery.parse("IN:test")
        let query2 = PaletteQuery.parse("Project:test")
        XCTAssertEqual(query1.projectFilter, "test")
        XCTAssertEqual(query2.projectFilter, "test")
    }

    func testEmptyProjectFilter() {
        let query = PaletteQuery.parse("foo in:")
        XCTAssertEqual(query.searchText, "foo")
        XCTAssertNil(query.projectFilter)
    }

    func testMultipleTokensWithFilter() {
        let query = PaletteQuery.parse("foo bar baz in:dashboard")
        XCTAssertEqual(query.searchTokens, ["foo", "bar", "baz"])
        XCTAssertEqual(query.projectFilter, "dashboard")
    }

    func testWhitespaceHandling() {
        let query = PaletteQuery.parse("  foo   bar  ")
        XCTAssertEqual(query.searchTokens, ["foo", "bar"])
    }
}
