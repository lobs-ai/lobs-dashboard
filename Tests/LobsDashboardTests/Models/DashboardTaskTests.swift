import XCTest
@testable import LobsDashboard

final class DashboardTaskTests: XCTestCase {

    func testMinimalTaskRoundTrip() throws {
        let json = TestFixtures.minimalTaskJSON.data(using: .utf8)!
        let task = try TestFixtures.decoder().decode(DashboardTask.self, from: json)

        XCTAssertEqual(task.id, "minimal-task")
        XCTAssertEqual(task.title, "Minimal Task")
        XCTAssertEqual(task.status, .active)
        XCTAssertEqual(task.owner, .rafe)
        XCTAssertNil(task.workState)
        XCTAssertNil(task.projectId)
    }

    func testFullTaskRoundTrip() throws {
        let json = TestFixtures.fullTaskJSON.data(using: .utf8)!
        let task = try TestFixtures.decoder().decode(DashboardTask.self, from: json)

        XCTAssertEqual(task.id, "full-task")
        XCTAssertEqual(task.title, "Full Task")
        XCTAssertEqual(task.status, .active)
        XCTAssertEqual(task.owner, .lobs)
        XCTAssertEqual(task.workState, .inProgress)
        XCTAssertEqual(task.reviewState, .pending)
        XCTAssertEqual(task.projectId, "test-project")
        XCTAssertEqual(task.notes, "Task notes")
    }

    func testOptionalFieldsAreNil() throws {
        let minimal = TestFixtures.makeTask()
        XCTAssertNil(minimal.artifactPath)
        XCTAssertNil(minimal.notes)
        XCTAssertNil(minimal.startedAt)
        XCTAssertNil(minimal.finishedAt)
        XCTAssertNil(minimal.sortOrder)
        XCTAssertNil(minimal.blockedBy)
        XCTAssertNil(minimal.pinned)
        XCTAssertNil(minimal.shape)
        XCTAssertNil(minimal.githubIssueNumber)
    }
}
