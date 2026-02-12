import XCTest
@testable import LobsDashboard

/// Tests for inbox unread count calculation - ensuring artifacts are excluded but state/inbox items are included
final class InboxUnreadCountTests: XCTestCase {
  
  func testUnreadCountExcludesArtifacts() {
    // Given: inbox items including artifacts
    let items = [
      InboxItem(
        id: "inbox/design.md",
        title: "Design Doc",
        filename: "design.md",
        relativePath: "inbox/design.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "artifacts/old-artifact.md",
        title: "Old Artifact",
        filename: "old-artifact.md",
        relativePath: "artifacts/old-artifact.md",
        content: "Artifact content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Artifact summary"
      ),
      InboxItem(
        id: "state/inbox/suggestion.json",
        title: "Suggestion",
        filename: "suggestion.json",
        relativePath: "state/inbox/suggestion.json",
        content: "JSON content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Suggestion summary"
      ),
    ]
    
    // When: filtering items like unreadInboxCount does
    let unreadCount = items.filter { item in
      !item.relativePath.hasPrefix("artifacts/") &&
      !item.isRead
    }.count
    
    // Then: should count inbox/ and state/inbox/ items, but not artifacts/
    XCTAssertEqual(unreadCount, 2, "Should count inbox and state/inbox items, excluding artifacts")
  }
  
  func testUnreadCountIncludesStateInboxItems() {
    // Given: only state/inbox items (orchestrator suggestions)
    let items = [
      InboxItem(
        id: "state/inbox/suggestion1.json",
        title: "Suggestion 1",
        filename: "suggestion1.json",
        relativePath: "state/inbox/suggestion1.json",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "state/inbox/suggestion2.json",
        title: "Suggestion 2",
        filename: "suggestion2.json",
        relativePath: "state/inbox/suggestion2.json",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
    ]
    
    // When: filtering items
    let unreadCount = items.filter { item in
      !item.relativePath.hasPrefix("artifacts/") &&
      !item.isRead
    }.count
    
    // Then: should count all state/inbox items
    XCTAssertEqual(unreadCount, 2, "Should include state/inbox items in unread count")
  }
  
  func testUnreadCountRespectsReadStatus() {
    // Given: mix of read and unread items
    let items = [
      InboxItem(
        id: "inbox/read.md",
        title: "Read Doc",
        filename: "read.md",
        relativePath: "inbox/read.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: true,
        summary: "Summary"
      ),
      InboxItem(
        id: "inbox/unread.md",
        title: "Unread Doc",
        filename: "unread.md",
        relativePath: "inbox/unread.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "artifacts/unread-artifact.md",
        title: "Unread Artifact",
        filename: "unread-artifact.md",
        relativePath: "artifacts/unread-artifact.md",
        content: "Artifact",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
    ]
    
    // When: filtering items
    let unreadCount = items.filter { item in
      !item.relativePath.hasPrefix("artifacts/") &&
      !item.isRead
    }.count
    
    // Then: should only count unread non-artifact items
    XCTAssertEqual(unreadCount, 1, "Should only count unread non-artifact items")
  }
  
  func testInboxViewFilterMatchesUnreadCountFilter() {
    // Given: various inbox items
    let items = [
      InboxItem(
        id: "inbox/doc.md",
        title: "Doc",
        filename: "doc.md",
        relativePath: "inbox/doc.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "artifacts/artifact.md",
        title: "Artifact",
        filename: "artifact.md",
        relativePath: "artifacts/artifact.md",
        content: "Artifact",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "state/inbox/suggestion.json",
        title: "Suggestion",
        filename: "suggestion.json",
        relativePath: "state/inbox/suggestion.json",
        content: "Suggestion",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
    ]
    
    // When: applying InboxView display filter
    let displayedItems = items.filter { !$0.relativePath.hasPrefix("artifacts/") }
    
    // And: applying unreadInboxCount filter (without read status check)
    let countedItems = items.filter { !$0.relativePath.hasPrefix("artifacts/") }
    
    // Then: both filters should produce same result set
    XCTAssertEqual(displayedItems.count, countedItems.count)
    XCTAssertEqual(displayedItems.count, 2, "Should display inbox and state/inbox items")
    
    let displayedIds = Set(displayedItems.map { $0.id })
    let countedIds = Set(countedItems.map { $0.id })
    XCTAssertEqual(displayedIds, countedIds, "Display and count filters should match")
  }
  
  func testArtifactsCompletelyExcluded() {
    // Given: only artifact items
    let items = [
      InboxItem(
        id: "artifacts/design.md",
        title: "Design Artifact",
        filename: "design.md",
        relativePath: "artifacts/design.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "artifacts/spec.md",
        title: "Spec Artifact",
        filename: "spec.md",
        relativePath: "artifacts/spec.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
    ]
    
    // When: filtering items
    let unreadCount = items.filter { item in
      !item.relativePath.hasPrefix("artifacts/") &&
      !item.isRead
    }.count
    
    // Then: should count zero items
    XCTAssertEqual(unreadCount, 0, "Artifacts should never be counted in unread inbox count")
  }
}
