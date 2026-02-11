import XCTest
@testable import LobsDashboard

final class GitHubProjectConfigCodableTests: XCTestCase {

    func testNewFormatDecode() throws {
        let json = """
        {
          "repo": "owner/reponame",
          "labelFilter": ["bug", "feature"]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(GitHubProjectConfig.self, from: json)
        XCTAssertEqual(config.repo, "owner/reponame")
        XCTAssertEqual(config.labelFilter, ["bug", "feature"])
    }

    func testLegacyFormatMigration_OwnerAndRepoName() throws {
        // Old format had separate owner/repoName fields
        let legacyJSON = """
        {
          "owner": "testowner",
          "repoName": "testrepo"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(GitHubProjectConfig.self, from: legacyJSON)
        XCTAssertEqual(config.repo, "testowner/testrepo")
    }

    func testLegacyFormatMigration_SyncLabelsToLabelFilter() throws {
        // Old format used "syncLabels" instead of "labelFilter"
        let legacyJSON = """
        {
          "owner": "org",
          "repoName": "project",
          "syncLabels": ["status:active"]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(GitHubProjectConfig.self, from: legacyJSON)
        XCTAssertEqual(config.repo, "org/project")
        XCTAssertEqual(config.labelFilter, ["status:active"])
    }

    func testEncodeUsesNewFormat() throws {
        let config = GitHubProjectConfig(
            repo: "owner/repo",
            labelFilter: ["label1", "label2"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should use new field names
        XCTAssertTrue(jsonString.contains("\"repo\""))
        XCTAssertTrue(jsonString.contains("\"labelFilter\""))

        // Should NOT use legacy field names
        XCTAssertFalse(jsonString.contains("\"owner\""))
        XCTAssertFalse(jsonString.contains("\"repoName\""))
        XCTAssertFalse(jsonString.contains("\"syncLabels\""))
    }

    func testMinimalConfigWithoutLabels() throws {
        let json = """
        {
          "repo": "owner/repo"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(GitHubProjectConfig.self, from: json)
        XCTAssertEqual(config.repo, "owner/repo")
        XCTAssertNil(config.labelFilter)
    }

    func testRoundTrip() throws {
        let original = GitHubProjectConfig(
            repo: "test/project",
            labelFilter: ["enhancement"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(GitHubProjectConfig.self, from: data)

        XCTAssertEqual(decoded.repo, original.repo)
        XCTAssertEqual(decoded.labelFilter, original.labelFilter)
    }
}
