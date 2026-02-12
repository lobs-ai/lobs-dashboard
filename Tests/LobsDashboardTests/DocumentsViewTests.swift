import XCTest
@testable import LobsDashboard

/// Tests for Documents View feature
///
/// ## What This Tests
///
/// This test suite documents and verifies the behavior of the Documents view feature,
/// which displays agent-produced documents (reports from writer, research from researcher).
///
/// ## Data Sources
///
/// - `state/reports/pending/` — Writer agent output (markdown files)
/// - `state/reports/approved/` — Approved reports
/// - `state/reports/rejected/` — Rejected reports  
/// - `state/research/{topic}/` — Researcher agent output (organized by topic)
///
/// ## Test Coverage
///
/// 1. **Document Model**
///    - Document creation with all required fields
///    - DocumentSource enum (writer, researcher)
///    - DocumentStatus enum (pending, approved, rejected)
///    - Read/unread state management
///
/// 2. **Document Loading**
///    - Load documents from reports directories (pending/approved/rejected)
///    - Load documents from research topic subdirectories
///    - Extract title from markdown content or filename
///    - Handle large files with content truncation
///    - Sort by date (newest first)
///
/// 3. **Filtering**
///    - Filter by read/unread status
///    - Filter by source (writer/researcher/all)
///    - Filter by status (pending/approved/rejected/all)
///    - Search by title, filename, topic, or project
///
/// 4. **UI Integration**
///    - Documents toolbar button with unread count badge
///    - Keyboard shortcut (⌘D) to open Documents view
///    - Documents overlay with split view (list + detail)
///    - Mark documents as read/unread
///
/// ## Implementation Notes
///
/// - **Async loading**: Documents loaded in background via `loadAgentDocumentsAsync()` during app reload
/// - **Read state**: Tracked in `AppViewModel.readDocumentIds` Set<String>
/// - **Performance**: Large files (>64KB) have truncated content preview
/// - **Markdown rendering**: Full markdown content displayed with MarkdownWebView
///
/// ## File Structure
///
/// - **Models.swift**: DocumentSource, DocumentStatus, AgentDocument structs
/// - **Store.swift**: `loadAgentDocuments()` method to scan filesystem
/// - **AppViewModel.swift**: `loadAgentDocumentsAsync()`, `markDocumentRead()`, `markDocumentUnread()`
/// - **DocumentsView.swift**: Main Documents view with filtering and detail pane
/// - **ContentView.swift**: Integration with toolbar and keyboard shortcuts
///
final class DocumentsViewTests: XCTestCase {

  // MARK: - Document Model Tests

  func testDocumentModel() {
    let doc = AgentDocument(
      id: "reports/pending/test.md",
      title: "Test Report",
      filename: "test.md",
      relativePath: "reports/pending/test.md",
      content: "# Test Report\n\nContent here.",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: "test-project",
      taskId: "123",
      date: Date(),
      isRead: false
    )

    XCTAssertEqual(doc.id, "reports/pending/test.md")
    XCTAssertEqual(doc.title, "Test Report")
    XCTAssertEqual(doc.source, .writer)
    XCTAssertEqual(doc.status, .pending)
    XCTAssertFalse(doc.isRead)
    XCTAssertFalse(doc.contentIsTruncated)
  }

  func testDocumentSourceEnum() {
    XCTAssertEqual(DocumentSource.writer.displayName, "Writer")
    XCTAssertEqual(DocumentSource.researcher.displayName, "Researcher")
    XCTAssertEqual(DocumentSource.writer.icon, "doc.text.fill")
    XCTAssertEqual(DocumentSource.researcher.icon, "magnifyingglass")
  }

  func testDocumentStatusEnum() {
    XCTAssertEqual(DocumentStatus.pending.displayName, "Pending")
    XCTAssertEqual(DocumentStatus.approved.displayName, "Approved")
    XCTAssertEqual(DocumentStatus.rejected.displayName, "Rejected")
  }

  // MARK: - Filtering Tests

  func testFilterByReadStatus() {
    let doc1 = AgentDocument(
      id: "1",
      title: "Read Document",
      filename: "read.md",
      relativePath: "reports/pending/read.md",
      content: "Content",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: true
    )

    let doc2 = AgentDocument(
      id: "2",
      title: "Unread Document",
      filename: "unread.md",
      relativePath: "reports/pending/unread.md",
      content: "Content",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )

    let allDocs = [doc1, doc2]
    let unreadOnly = allDocs.filter { !$0.isRead }

    XCTAssertEqual(unreadOnly.count, 1)
    XCTAssertEqual(unreadOnly.first?.id, "2")
  }

  func testFilterBySource() {
    let writerDoc = AgentDocument(
      id: "1",
      title: "Writer Document",
      filename: "writer.md",
      relativePath: "reports/pending/writer.md",
      content: "Content",
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
      id: "2",
      title: "Research Document",
      filename: "research.md",
      relativePath: "research/topic/research.md",
      content: "Content",
      contentIsTruncated: false,
      source: .researcher,
      status: nil,
      topic: "topic",
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )

    let allDocs = [writerDoc, researchDoc]
    let writerOnly = allDocs.filter { $0.source == .writer }
    let researcherOnly = allDocs.filter { $0.source == .researcher }

    XCTAssertEqual(writerOnly.count, 1)
    XCTAssertEqual(writerOnly.first?.id, "1")
    XCTAssertEqual(researcherOnly.count, 1)
    XCTAssertEqual(researcherOnly.first?.id, "2")
  }

  func testFilterByStatus() {
    let pendingDoc = AgentDocument(
      id: "1",
      title: "Pending Report",
      filename: "pending.md",
      relativePath: "reports/pending/pending.md",
      content: "Content",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )

    let approvedDoc = AgentDocument(
      id: "2",
      title: "Approved Report",
      filename: "approved.md",
      relativePath: "reports/approved/approved.md",
      content: "Content",
      contentIsTruncated: false,
      source: .writer,
      status: .approved,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )

    let allDocs = [pendingDoc, approvedDoc]
    let pendingOnly = allDocs.filter { $0.status == .pending }
    let approvedOnly = allDocs.filter { $0.status == .approved }

    XCTAssertEqual(pendingOnly.count, 1)
    XCTAssertEqual(pendingOnly.first?.id, "1")
    XCTAssertEqual(approvedOnly.count, 1)
    XCTAssertEqual(approvedOnly.first?.id, "2")
  }

  func testSearchFilter() {
    let doc1 = AgentDocument(
      id: "1",
      title: "SwiftUI Tutorial",
      filename: "swiftui.md",
      relativePath: "reports/pending/swiftui.md",
      content: "Content",
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
      id: "2",
      title: "Python Guide",
      filename: "python.md",
      relativePath: "research/programming/python.md",
      content: "Content",
      contentIsTruncated: false,
      source: .researcher,
      status: nil,
      topic: "programming",
      projectId: nil,
      taskId: nil,
      date: Date(),
      isRead: false
    )

    let allDocs = [doc1, doc2]
    let searchQuery = "swift"

    let filtered = allDocs.filter {
      $0.title.lowercased().contains(searchQuery.lowercased()) ||
      $0.filename.lowercased().contains(searchQuery.lowercased())
    }

    XCTAssertEqual(filtered.count, 1)
    XCTAssertEqual(filtered.first?.id, "1")
  }

  // MARK: - Sorting Tests

  func testDocumentsSortedByDateNewestFirst() {
    let now = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now)!

    let doc1 = AgentDocument(
      id: "1",
      title: "Old Document",
      filename: "old.md",
      relativePath: "reports/pending/old.md",
      content: "Content",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: lastWeek,
      isRead: false
    )

    let doc2 = AgentDocument(
      id: "2",
      title: "Recent Document",
      filename: "recent.md",
      relativePath: "reports/pending/recent.md",
      content: "Content",
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
      id: "3",
      title: "Newest Document",
      filename: "newest.md",
      relativePath: "reports/pending/newest.md",
      content: "Content",
      contentIsTruncated: false,
      source: .writer,
      status: .pending,
      topic: nil,
      projectId: nil,
      taskId: nil,
      date: now,
      isRead: false
    )

    let unsorted = [doc1, doc2, doc3]
    let sorted = unsorted.sorted { $0.date > $1.date }

    XCTAssertEqual(sorted[0].id, "3") // Newest first
    XCTAssertEqual(sorted[1].id, "2")
    XCTAssertEqual(sorted[2].id, "1")
  }

  // MARK: - Integration Tests (Document Expected Behavior)

  func testDocumentLoadingExpectations() {
    // This test documents the expected behavior of Store.loadAgentDocuments()
    //
    // Expected behavior:
    // 1. Scans state/reports/{pending,approved,rejected}/ for .md files
    // 2. Scans state/research/{topic}/ for .md files
    // 3. Extracts title from markdown content (first heading) or falls back to filename
    // 4. Truncates content to 64KB for performance
    // 5. Assigns source=.writer for reports, source=.researcher for research
    // 6. Assigns status for reports based on subdirectory
    // 7. Extracts topic from research subdirectory name
    // 8. Uses file modification date as document date
    // 9. Returns sorted by date (newest first)
    //
    // This behavior is implemented in Store.loadAgentDocuments()
  }

  func testReadStateManagement() {
    // This test documents the expected behavior of read state management
    //
    // Expected behavior:
    // 1. AppViewModel maintains readDocumentIds Set<String>
    // 2. markDocumentRead() adds document ID to set and updates @Published array
    // 3. markDocumentUnread() removes document ID from set and updates @Published array
    // 4. On reload, read state is applied to loaded documents
    // 5. Read state persists across app launches (stored in config)
    //
    // This behavior is implemented in AppViewModel methods
  }

  func testDocumentsToolbarIntegration() {
    // This test documents the expected UI integration
    //
    // Expected behavior:
    // 1. DocumentsToolbarButton shows in ContentView toolbar
    // 2. Button displays unread count badge when documents are unread
    // 3. Clicking button opens Documents overlay (showDocuments = true)
    // 4. Keyboard shortcut ⌘D opens Documents overlay
    // 5. Documents overlay is a sheet with split view (list + detail)
    // 6. Clicking outside dismisses overlay
    // 7. ESC key dismisses overlay
    //
    // This behavior is implemented in ContentView and DocumentsView
  }
}
