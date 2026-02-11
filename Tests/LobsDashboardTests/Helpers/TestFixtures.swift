import Foundation
@testable import LobsDashboard

/// Factory methods for creating test fixtures
enum TestFixtures {

    // MARK: - Projects

    static func makeProject(
        id: String = "test-project",
        title: String = "Test Project",
        type: ProjectType? = .kanban,
        tracking: TrackingMode? = .local,
        github: GitHubProjectConfig? = nil,
        archived: Bool? = false
    ) -> Project {
        let now = Date()
        return Project(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            notes: nil,
            archived: archived,
            type: type,
            sortOrder: nil,
            tracking: tracking,
            github: github
        )
    }

    // MARK: - Tasks

    static func makeTask(
        id: String = "test-task",
        title: String = "Test Task",
        status: TaskStatus = .active,
        owner: TaskOwner = .rafe,
        workState: WorkState? = .notStarted,
        reviewState: ReviewState? = .pending,
        projectId: String? = "test-project"
    ) -> DashboardTask {
        let now = Date()
        return DashboardTask(
            id: id,
            title: title,
            status: status,
            owner: owner,
            createdAt: now,
            updatedAt: now,
            workState: workState,
            reviewState: reviewState,
            projectId: projectId,
            artifactPath: nil,
            notes: nil
        )
    }

    // MARK: - Research Requests

    static func makeResearchRequest(
        id: String = "test-request",
        projectId: String = "test-project",
        prompt: String = "Test research prompt",
        status: ResearchRequestStatus = .open,
        priority: ResearchPriority? = .normal,
        deliverables: [RequestDeliverable]? = nil
    ) -> ResearchRequest {
        let now = Date()
        return ResearchRequest(
            id: id,
            projectId: projectId,
            tileId: nil,
            prompt: prompt,
            status: status,
            response: nil,
            author: "rafe",
            priority: priority,
            deliverables: deliverables,
            editHistory: nil,
            parentRequestId: nil,
            assignedWorker: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - JSON Strings

    // MARK: - JSON Decoder Helper

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: str) { return date }
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
        }
        return d
    }

    static let minimalProjectJSON = """
    {
      "id": "minimal",
      "title": "Minimal Project",
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z"
    }
    """

    static let fullProjectJSON = """
    {
      "id": "full",
      "title": "Full Project",
      "type": "kanban",
      "tracking": "local",
      "archived": false,
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z",
      "notes": "Test notes"
    }
    """

    static let minimalTaskJSON = """
    {
      "id": "minimal-task",
      "title": "Minimal Task",
      "status": "active",
      "owner": "rafe",
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z"
    }
    """

    static let fullTaskJSON = """
    {
      "id": "full-task",
      "title": "Full Task",
      "status": "active",
      "owner": "lobs",
      "workState": "in_progress",
      "reviewState": "pending",
      "projectId": "test-project",
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z",
      "notes": "Task notes"
    }
    """
}
