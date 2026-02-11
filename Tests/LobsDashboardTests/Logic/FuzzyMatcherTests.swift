import XCTest
@testable import LobsDashboard

final class FuzzyMatcherTests: XCTestCase {

    func testExactMatch() {
        let score = FuzzyMatcher.score(queryTokens: ["test"], target: "test")
        XCTAssertNotNil(score)
        XCTAssertEqual(score, 2000) // Exact match bonus
    }

    func testPrefixMatch() {
        let score = FuzzyMatcher.score(queryTokens: ["tes"], target: "test")
        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score!, 1000) // Prefix match
    }

    func testWordStartMatch() {
        let score = FuzzyMatcher.score(queryTokens: ["bar"], target: "foo bar baz")
        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score!, 1000) // Word-start match
    }

    func testSubsequenceMatch() {
        let score = FuzzyMatcher.score(queryTokens: ["fbb"], target: "foo bar baz")
        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score!, 0)
    }

    func testNoMatch() {
        let score = FuzzyMatcher.score(queryTokens: ["xyz"], target: "foo bar")
        XCTAssertNil(score)
    }

    func testMultiTokenMatch() {
        let score = FuzzyMatcher.score(queryTokens: ["foo", "bar"], target: "foo bar baz")
        XCTAssertNotNil(score)
    }

    func testMultiTokenPartialMatch_ShouldFail() {
        let score = FuzzyMatcher.score(queryTokens: ["foo", "xyz"], target: "foo bar")
        XCTAssertNil(score) // Second token doesn't match
    }

    func testCaseInsensitive() {
        let score1 = FuzzyMatcher.score(queryTokens: ["TEST"], target: "test")
        let score2 = FuzzyMatcher.score(queryTokens: ["test"], target: "TEST")
        XCTAssertNotNil(score1)
        XCTAssertNotNil(score2)
        XCTAssertEqual(score1, score2)
    }

    func testRankingOrder_ExactBeatsPrefixBeatsSubsequence() {
        let exact = FuzzyMatcher.score(queryTokens: ["test"], target: "test")!
        let prefix = FuzzyMatcher.score(queryTokens: ["tes"], target: "test")!
        let subsequence = FuzzyMatcher.score(queryTokens: ["tt"], target: "test")!

        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, subsequence)
    }

    func testEmptyTarget() {
        let score = FuzzyMatcher.score(queryTokens: ["test"], target: "")
        XCTAssertNil(score)
    }

    func testEmptyQuery() {
        let score = FuzzyMatcher.score(queryTokens: [], target: "test")
        XCTAssertNotNil(score)
        XCTAssertEqual(score, 0)
    }

    func testConsecutiveMatchBonus() {
        // "abc" in "abc" should score higher than "abc" in "a.b.c"
        let consecutive = FuzzyMatcher.score(queryTokens: ["abc"], target: "abc")!
        let scattered = FuzzyMatcher.score(queryTokens: ["abc"], target: "a.b.c")!
        XCTAssertGreaterThan(consecutive, scattered)
    }
}
