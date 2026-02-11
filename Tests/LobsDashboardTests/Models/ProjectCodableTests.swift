import XCTest
@testable import LobsDashboard

final class ProjectCodableTests: XCTestCase {

    func testMinimalProjectRoundTrip() throws {
        let json = TestFixtures.minimalProjectJSON.data(using: .utf8)!
        let project = try TestFixtures.decoder().decode(Project.self, from: json)

        XCTAssertEqual(project.id, "minimal")
        XCTAssertEqual(project.title, "Minimal Project")
        XCTAssertNil(project.type)
        XCTAssertNil(project.tracking)
        XCTAssertNil(project.github)
    }

    func testFullProjectRoundTrip() throws {
        let json = TestFixtures.fullProjectJSON.data(using: .utf8)!
        let project = try TestFixtures.decoder().decode(Project.self, from: json)

        XCTAssertEqual(project.id, "full")
        XCTAssertEqual(project.title, "Full Project")
        XCTAssertEqual(project.type, .kanban)
        XCTAssertEqual(project.tracking, .local)
        XCTAssertEqual(project.archived, false)
        XCTAssertEqual(project.notes, "Test notes")
    }

    func testLegacyAccessors() throws {
        // Test that legacy property accessors work (syncMode -> tracking, githubConfig -> github)
        let project = TestFixtures.makeProject(
            tracking: .github,
            github: GitHubProjectConfig(repo: "owner/repo")
        )

        XCTAssertEqual(project.syncMode, .github) // Legacy accessor
        XCTAssertEqual(project.githubConfig?.repo, "owner/repo") // Legacy accessor
    }

    func testResolvedTypeDefaultsToKanban() throws {
        let project = TestFixtures.makeProject(type: nil)
        XCTAssertEqual(project.resolvedType, .kanban)
    }

    func testResolvedTrackingDefaultsToLocal() throws {
        let project = TestFixtures.makeProject(tracking: nil)
        XCTAssertEqual(project.resolvedTracking, .local)
        XCTAssertEqual(project.resolvedSyncMode, .local) // Legacy accessor
    }

    func testEncodePreservesNewFormat() throws {
        let project = TestFixtures.makeProject(
            tracking: .github,
            github: GitHubProjectConfig(repo: "test/repo")
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(project)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should encode with new field names
        XCTAssertTrue(jsonString.contains("\"tracking\""))
        XCTAssertTrue(jsonString.contains("\"github\""))

        // Should NOT encode legacy field names
        XCTAssertFalse(jsonString.contains("\"syncMode\""))
        XCTAssertFalse(jsonString.contains("\"githubConfig\""))
    }
}
