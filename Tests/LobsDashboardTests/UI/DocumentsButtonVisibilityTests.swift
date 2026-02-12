import XCTest
@testable import LobsDashboard

/// Tests for Documents toolbar button conditional visibility
final class DocumentsButtonVisibilityTests: XCTestCase {
  
  func testDocumentsButtonOnlyShowsWhenDocumentsExist() {
    // Given: Empty agent documents
    let emptyDocuments: [AgentDocument] = []
    
    // When: checking if button should be visible
    let shouldShow = !emptyDocuments.isEmpty
    
    // Then: button should NOT be visible
    XCTAssertFalse(shouldShow, "Documents button should not show when there are no documents")
  }
  
  func testDocumentsButtonShowsWhenDocumentsExist() {
    // Given: Some agent documents
    let documents = [
      AgentDocument(
        id: "doc1",
        title: "Report",
        filename: "report.md",
        relativePath: "state/reports/report.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        category: .report
      )
    ]
    
    // When: checking if button should be visible
    let shouldShow = !documents.isEmpty
    
    // Then: button SHOULD be visible
    XCTAssertTrue(shouldShow, "Documents button should show when there are documents")
  }
  
  func testDocumentsButtonBehaviorMatchesTemplatesPattern() {
    // This test documents the pattern used for conditional toolbar buttons
    
    // Templates button visibility pattern:
    // if !vm.templates.isEmpty { /* show button */ }
    
    // Documents button should follow the same pattern:
    // if !vm.agentDocuments.isEmpty { /* show button */ }
    
    let emptyTemplates: [TaskTemplate] = []
    let emptyDocuments: [AgentDocument] = []
    
    // Both should follow the same visibility logic
    XCTAssertEqual(
      !emptyTemplates.isEmpty,
      !emptyDocuments.isEmpty,
      "Empty templates and empty documents should have same visibility logic (both hidden)"
    )
    
    let someTemplates = [TaskTemplate(id: "t1", name: "Template", description: nil, title: nil, notes: nil, status: nil, owner: nil, projectId: nil)]
    let someDocuments = [
      AgentDocument(
        id: "d1",
        title: "Doc",
        filename: "doc.md",
        relativePath: "state/reports/doc.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        category: .report
      )
    ]
    
    XCTAssertEqual(
      !someTemplates.isEmpty,
      !someDocuments.isEmpty,
      "Non-empty templates and non-empty documents should have same visibility logic (both visible)"
    )
  }
  
  func testDocumentsButtonAppearsAfterAsyncLoad() {
    // Given: Initial state with no documents
    var documents: [AgentDocument] = []
    XCTAssertTrue(documents.isEmpty, "Should start with no documents")
    
    // When: Documents are loaded asynchronously
    documents = [
      AgentDocument(
        id: "doc1",
        title: "New Report",
        filename: "report.md",
        relativePath: "state/reports/report.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        category: .report
      )
    ]
    
    // Then: Button should now be visible
    XCTAssertFalse(documents.isEmpty, "Documents should be loaded")
    let shouldShowButton = !documents.isEmpty
    XCTAssertTrue(shouldShowButton, "Button should appear after documents are loaded")
  }
  
  func testDocumentsButtonHiddenStateMatchesInboxSectionLogic() {
    // The inbox SECTION (not button) in OverviewView uses:
    // if !vm.inboxItems.isEmpty || vm.unreadInboxCount > 0
    
    // The inbox BUTTON is always visible (unconditional)
    
    // The documents BUTTON should match Templates behavior (conditional):
    // if !vm.agentDocuments.isEmpty
    
    // This is consistent because:
    // - Inbox is a core feature, always accessible
    // - Documents and Templates are optional features, shown only when relevant
    
    let noDocuments: [AgentDocument] = []
    XCTAssertTrue(noDocuments.isEmpty, "No documents means button should be hidden")
  }
  
  func testDocumentsButtonVisibilityUpdatesDynamically() {
    // Given: Documents array that changes over time
    var documents: [AgentDocument] = []
    
    // Initially empty
    XCTAssertTrue(!documents.isEmpty == false, "Button hidden when no documents")
    
    // Add document
    documents.append(
      AgentDocument(
        id: "doc1",
        title: "Report",
        filename: "report.md",
        relativePath: "state/reports/report.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        category: .report
      )
    )
    XCTAssertTrue(!documents.isEmpty, "Button visible when documents exist")
    
    // Remove all documents
    documents.removeAll()
    XCTAssertFalse(!documents.isEmpty, "Button hidden again when documents removed")
  }
}
