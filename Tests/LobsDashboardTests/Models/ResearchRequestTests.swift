import XCTest
@testable import LobsDashboard

final class ResearchRequestTests: XCTestCase {

    func testAllDeliverablesFulfilled_EmptyDeliverables() {
        let request = TestFixtures.makeResearchRequest(deliverables: nil)
        XCTAssertTrue(request.allDeliverablesFulfilled)
    }

    func testAllDeliverablesFulfilled_AllFulfilled() {
        let deliverables = [
            RequestDeliverable(id: "1", kind: "markdown", label: "Doc", fulfilled: true),
            RequestDeliverable(id: "2", kind: "summary", label: "Summary", fulfilled: true)
        ]
        let request = TestFixtures.makeResearchRequest(deliverables: deliverables)
        XCTAssertTrue(request.allDeliverablesFulfilled)
    }

    func testAllDeliverablesFulfilled_SomeUnfulfilled() {
        let deliverables = [
            RequestDeliverable(id: "1", kind: "markdown", label: "Doc", fulfilled: true),
            RequestDeliverable(id: "2", kind: "summary", label: "Summary", fulfilled: false)
        ]
        let request = TestFixtures.makeResearchRequest(deliverables: deliverables)
        XCTAssertFalse(request.allDeliverablesFulfilled)
    }

    func testDeliverableProgress_None() {
        let request = TestFixtures.makeResearchRequest(deliverables: nil)
        let (fulfilled, total) = request.deliverableProgress
        XCTAssertEqual(fulfilled, 0)
        XCTAssertEqual(total, 0)
    }

    func testDeliverableProgress_PartiallyFulfilled() {
        let deliverables = [
            RequestDeliverable(id: "1", kind: "markdown", label: "Doc", fulfilled: true),
            RequestDeliverable(id: "2", kind: "summary", label: "Summary", fulfilled: false),
            RequestDeliverable(id: "3", kind: "links", label: "Links", fulfilled: true)
        ]
        let request = TestFixtures.makeResearchRequest(deliverables: deliverables)
        let (fulfilled, total) = request.deliverableProgress
        XCTAssertEqual(fulfilled, 2)
        XCTAssertEqual(total, 3)
    }

    func testCurrentVersion_NoEditHistory() {
        let request = TestFixtures.makeResearchRequest()
        XCTAssertEqual(request.currentVersion, 1)
    }

    func testCurrentVersion_WithEdits() {
        let now = Date()
        let editHistory = [
            RequestEditVersion(id: "v1", prompt: "First edit", editedAt: now, editedBy: "rafe"),
            RequestEditVersion(id: "v2", prompt: "Second edit", editedAt: now, editedBy: "rafe")
        ]
        var request = TestFixtures.makeResearchRequest()
        request.editHistory = editHistory
        XCTAssertEqual(request.currentVersion, 3) // Original + 2 edits
    }

    func testResolvedPriority_NilDefaultsToNormal() {
        let request = TestFixtures.makeResearchRequest(priority: nil)
        XCTAssertEqual(request.resolvedPriority, .normal)
    }

    func testResolvedPriority_ExplicitValue() {
        let request = TestFixtures.makeResearchRequest(priority: .urgent)
        XCTAssertEqual(request.resolvedPriority, .urgent)
    }

    func testMissingProjectIdDefaultsToUnknown() throws {
        let json = """
        {
          "id": "test",
          "prompt": "Test prompt",
          "status": "open",
          "createdAt": "2024-01-01T00:00:00Z",
          "updatedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let request = try TestFixtures.decoder().decode(ResearchRequest.self, from: json)
        XCTAssertEqual(request.projectId, "unknown")
    }

    func testRoundTripWithAllFields() throws {
        let deliverables = [
            RequestDeliverable(id: "1", kind: "markdown", label: "Main doc", fulfilled: true)
        ]
        let original = TestFixtures.makeResearchRequest(
            prompt: "Research prompt",
            priority: .high,
            deliverables: deliverables
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ResearchRequest.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.projectId, original.projectId)
        XCTAssertEqual(decoded.prompt, original.prompt)
        XCTAssertEqual(decoded.priority, original.priority)
        XCTAssertEqual(decoded.deliverables?.count, 1)
    }
}
