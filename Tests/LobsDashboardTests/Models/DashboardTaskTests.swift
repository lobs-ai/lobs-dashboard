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
        XCTAssertNil(minimal.agent)
    }

    func testAgentFieldBackwardsCompatibility() throws {
        // Legacy task JSON without agent field should decode with agent=nil
        let legacyJSON = """
        {
            "id": "legacy-task",
            "title": "Legacy Task",
            "status": "active",
            "owner": "lobs",
            "createdAt": "2024-01-01T12:00:00Z",
            "updatedAt": "2024-01-01T12:00:00Z"
        }
        """
        let json = legacyJSON.data(using: .utf8)!
        let task = try TestFixtures.decoder().decode(DashboardTask.self, from: json)

        XCTAssertNil(task.agent, "Legacy tasks without agent field should decode with agent=nil")
    }

    func testAgentFieldEncodingDecoding() throws {
        // Task with agent field should encode and decode properly
        let taskWithAgent = DashboardTask(
            id: "test-task",
            title: "Test Task",
            status: .active,
            owner: .lobs,
            createdAt: Date(),
            updatedAt: Date(),
            agent: "programmer"
        )

        let encoded = try TestFixtures.encoder().encode(taskWithAgent)
        let decoded = try TestFixtures.decoder().decode(DashboardTask.self, from: encoded)

        XCTAssertEqual(decoded.agent, "programmer", "Agent field should persist through encode/decode")
    }

    func testAgentFieldSupportedTypes() throws {
        let agentTypes = ["programmer", "researcher", "reviewer", "writer", "architect"]

        for agentType in agentTypes {
            let task = DashboardTask(
                id: "test-\(agentType)",
                title: "Test \(agentType) Task",
                status: .active,
                owner: .lobs,
                createdAt: Date(),
                updatedAt: Date(),
                agent: agentType
            )

            let encoded = try TestFixtures.encoder().encode(task)
            let decoded = try TestFixtures.decoder().decode(DashboardTask.self, from: encoded)

            XCTAssertEqual(decoded.agent, agentType, "\(agentType) agent type should persist")
        }
    }
}
