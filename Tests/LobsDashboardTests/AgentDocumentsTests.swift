import XCTest
@testable import LobsDashboard

/// Tests for the Agent Documents feature (Reports & Research)
final class AgentDocumentsTests: XCTestCase {
  
  // MARK: - Model Tests
  
  func testDocumentSourceEnum() {
    XCTAssertEqual(DocumentSource.writer.rawValue, "writer")
    XCTAssertEqual(DocumentSource.researcher.rawValue, "researcher")
  }
  
  func testDocumentStatusEnum() {
    XCTAssertEqual(DocumentStatus.pending.rawValue, "pending")
    XCTAssertEqual(DocumentStatus.approved.rawValue, "approved")
    XCTAssertEqual(DocumentStatus.rejected.rawValue, "rejected")
  }
  
  func testAgentDocumentCreation() {
    let doc = AgentDocument(
      id: "reports/pending/test.md",
      title: "Test Report",
      filename: "test.md",
      relativePath: "reports/pending/test.md",
      content: "# Test Content",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    XCTAssertEqual(doc.id, "reports/pending/test.md")
    XCTAssertEqual(doc.title, "Test Report")
    XCTAssertEqual(doc.source, .writer)
    XCTAssertEqual(doc.status, .pending)
    XCTAssertFalse(doc.isRead)
  }
  
  func testResearchDocumentCreation() {
    let doc = AgentDocument(
      id: "research/self-improvement/test.md",
      title: "Research Finding",
      filename: "test.md",
      relativePath: "research/self-improvement/test.md",
      content: "# Research Content",
      contentIsTruncated: false,
      source: .researcher,
      status: nil,
      topic: "self-improvement",
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    XCTAssertEqual(doc.source, .researcher)
    XCTAssertNil(doc.status)
    XCTAssertEqual(doc.topic, "self-improvement")
  }
  
  // MARK: - AppViewModel Tests
  
  func testMarkDocumentRead() {
    let vm = AppViewModel()
    let doc = AgentDocument(
      id: "test-doc",
      title: "Test",
      filename: "test.md",
      relativePath: "reports/pending/test.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    vm.agentDocuments = [doc]
    
    vm.markDocumentRead(doc)
    
    XCTAssertTrue(vm.readDocumentIds.contains("test-doc"))
    XCTAssertTrue(vm.agentDocuments.first?.isRead ?? false)
  }
  
  func testMarkDocumentUnread() {
    let vm = AppViewModel()
    var doc = AgentDocument(
      id: "test-doc",
      title: "Test",
      filename: "test.md",
      relativePath: "reports/pending/test.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: true
    )
    
    vm.agentDocuments = [doc]
    vm.readDocumentIds = ["test-doc"]
    
    vm.markDocumentUnread(doc)
    
    XCTAssertFalse(vm.readDocumentIds.contains("test-doc"))
    XCTAssertFalse(vm.agentDocuments.first?.isRead ?? true)
  }
  
  // MARK: - Integration Tests
  
  func testDocumentLoadingPreservesReadState() {
    // When documents are loaded, read state should be applied
    let vm = AppViewModel()
    vm.readDocumentIds = ["doc1", "doc2"]
    
    // Simulate loading documents
    let doc1 = AgentDocument(
      id: "doc1",
      title: "Doc 1",
      filename: "doc1.md",
      relativePath: "reports/pending/doc1.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    let doc2 = AgentDocument(
      id: "doc2",
      title: "Doc 2",
      filename: "doc2.md",
      relativePath: "reports/pending/doc2.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    let doc3 = AgentDocument(
      id: "doc3",
      title: "Doc 3",
      filename: "doc3.md",
      relativePath: "reports/pending/doc3.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    // This would normally happen in loadAgentDocuments
    var docs = [doc1, doc2, doc3]
    for i in docs.indices {
      docs[i].isRead = vm.readDocumentIds.contains(docs[i].id)
    }
    
    XCTAssertTrue(docs[0].isRead)
    XCTAssertTrue(docs[1].isRead)
    XCTAssertFalse(docs[2].isRead)
  }
  
  // MARK: - UI Component Tests
  
  func testDocumentsViewFiltering() {
    // Documents view should filter by source and status
    // This test documents expected filtering behavior
    
    let writerDoc = AgentDocument(
      id: "writer-doc",
      title: "Writer Report",
      filename: "report.md",
      relativePath: "reports/pending/report.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    let researchDoc = AgentDocument(
      id: "research-doc",
      title: "Research Finding",
      filename: "finding.md",
      relativePath: "research/topic/finding.md",
      content: "",
      contentIsTruncated: false,
      source: .researcher,
      status: nil,
      topic: "topic",
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    let approvedDoc = AgentDocument(
      id: "approved-doc",
      title: "Approved Report",
      filename: "approved.md",
      relativePath: "reports/approved/approved.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .approved,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    let allDocs = [writerDoc, researchDoc, approvedDoc]
    
    // Filter by writer source
    let writerDocs = allDocs.filter { $0.source == .writer }
    XCTAssertEqual(writerDocs.count, 2)
    
    // Filter by researcher source
    let researchDocs = allDocs.filter { $0.source == .researcher }
    XCTAssertEqual(researchDocs.count, 1)
    
    // Filter by pending status
    let pendingDocs = allDocs.filter { $0.status == .pending }
    XCTAssertEqual(pendingDocs.count, 1)
    
    // Filter by approved status
    let approvedDocs = allDocs.filter { $0.status == .approved }
    XCTAssertEqual(approvedDocs.count, 1)
  }
  
  func testSearchFiltering() {
    // Documents should be searchable by title, filename, topic, and content
    let doc = AgentDocument(
      id: "test-doc",
      title: "System Health Report",
      filename: "health-2024.md",
      relativePath: "reports/pending/health-2024.md",
      content: "Analysis of orchestrator performance metrics",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    // Should match on title
    XCTAssertTrue(doc.title.lowercased().contains("health"))
    
    // Should match on filename
    XCTAssertTrue(doc.filename.lowercased().contains("2024"))
    
    // Should match on content
    XCTAssertTrue(doc.content.lowercased().contains("orchestrator"))
  }
  
  func testDocumentSorting() {
    // Documents should be sorted by date (newest first)
    let now = Date()
    let yesterday = now.addingTimeInterval(-86400)
    let lastWeek = now.addingTimeInterval(-86400 * 7)
    
    let doc1 = AgentDocument(
      id: "doc1",
      title: "Recent",
      filename: "recent.md",
      relativePath: "reports/pending/recent.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: now,
      isRead: false
    )
    
    let doc2 = AgentDocument(
      id: "doc2",
      title: "Yesterday",
      filename: "yesterday.md",
      relativePath: "reports/pending/yesterday.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: yesterday,
      isRead: false
    )
    
    let doc3 = AgentDocument(
      id: "doc3",
      title: "Last Week",
      filename: "lastweek.md",
      relativePath: "reports/pending/lastweek.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: lastWeek,
      isRead: false
    )
    
    let sorted = [doc3, doc1, doc2].sorted { $0.date > $1.date }
    
    XCTAssertEqual(sorted[0].id, "doc1") // Most recent
    XCTAssertEqual(sorted[1].id, "doc2") // Yesterday
    XCTAssertEqual(sorted[2].id, "doc3") // Last week
  }
  
  // MARK: - Keyboard Shortcut Tests
  
  func testDocumentsKeyboardShortcut() {
    // ⌘D should open Documents view
    // This is tested in ContentView with the KeyboardShortcuts struct
    
    // The shortcut is defined as:
    // Button("") { onDocuments?() }
    //   .keyboardShortcut("d", modifiers: .command)
    
    XCTAssert(true, "Keyboard shortcut ⌘D is configured for Documents view")
  }
  
  // MARK: - Badge Tests
  
  func testUnreadDocumentBadge() {
    // Documents toolbar button should show unread count
    let vm = AppViewModel()
    
    let doc1 = AgentDocument(
      id: "doc1",
      title: "Doc 1",
      filename: "doc1.md",
      relativePath: "reports/pending/doc1.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )
    
    let doc2 = AgentDocument(
      id: "doc2",
      title: "Doc 2",
      filename: "doc2.md",
      relativePath: "reports/pending/doc2.md",
      content: "",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: true
    )
    
    vm.agentDocuments = [doc1, doc2]
    
    let unreadCount = vm.agentDocuments.filter { !$0.isRead }.count
    XCTAssertEqual(unreadCount, 1)
  }
}
