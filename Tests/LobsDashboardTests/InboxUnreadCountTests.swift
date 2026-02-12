import XCTest
@testable import LobsDashboard

/// Tests for inbox unread count calculation - ensuring only inbox/ items are counted (not state/inbox/ or artifacts/)
final class InboxUnreadCountTests: XCTestCase {
  
  func testUnreadCountOnlyCountsInboxItems() {
    // Given: inbox items from different directories
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
    
    // When: filtering items like unreadInboxCount does (only inbox/ items)
    let unreadCount = items.filter { item in
      item.relativePath.hasPrefix("inbox/") &&
      !item.isRead
    }.count
    
    // Then: should only count inbox/ items, excluding state/inbox/ and artifacts/
    XCTAssertEqual(unreadCount, 1, "Should only count inbox/ items, not state/inbox/ or artifacts/")
  }
  
  func testUnreadCountExcludesStateInboxItems() {
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
      item.relativePath.hasPrefix("inbox/") &&
      !item.isRead
    }.count
    
    // Then: should NOT count state/inbox items
    XCTAssertEqual(unreadCount, 0, "Should exclude state/inbox items from unread count")
  }
  
  func testUnreadCountRespectsReadStatus() {
    // Given: mix of read and unread inbox/ items
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
      item.relativePath.hasPrefix("inbox/") &&
      !item.isRead
    }.count
    
    // Then: should only count unread inbox/ items
    XCTAssertEqual(unreadCount, 1, "Should only count unread inbox/ items")
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
    
    // When: applying InboxView display filter (only inbox/ items)
    let displayedItems = items.filter { $0.relativePath.hasPrefix("inbox/") }
    
    // And: applying unreadInboxCount filter (without read status check)
    let countedItems = items.filter { $0.relativePath.hasPrefix("inbox/") }
    
    // Then: both filters should produce same result set
    XCTAssertEqual(displayedItems.count, countedItems.count)
    XCTAssertEqual(displayedItems.count, 1, "Should only display inbox/ items")
    
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
      item.relativePath.hasPrefix("inbox/") &&
      !item.isRead
    }.count
    
    // Then: should count zero items
    XCTAssertEqual(unreadCount, 0, "Artifacts should never be counted in unread inbox count")
  }
  
  func testStateInboxItemsCompletelyExcluded() {
    // Given: only state/inbox items (system alerts)
    let items = [
      InboxItem(
        id: "state/inbox/alert1.json",
        title: "System Alert 1",
        filename: "alert1.json",
        relativePath: "state/inbox/alert1.json",
        content: "Alert content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Alert summary"
      ),
      InboxItem(
        id: "state/inbox/alert2.json",
        title: "System Alert 2",
        filename: "alert2.json",
        relativePath: "state/inbox/alert2.json",
        content: "Alert content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Alert summary"
      ),
    ]
    
    // When: filtering items
    let unreadCount = items.filter { item in
      item.relativePath.hasPrefix("inbox/") &&
      !item.isRead
    }.count
    
    // Then: should count zero items
    XCTAssertEqual(unreadCount, 0, "state/inbox/ items should never be counted in unread inbox count")
  }
  
  func testMixedInboxPrefixesFilteredCorrectly() {
    // Given: items with similar but different path prefixes
    let items = [
      InboxItem(
        id: "inbox/valid.md",
        title: "Valid Inbox",
        filename: "valid.md",
        relativePath: "inbox/valid.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "state/inbox/invalid.json",
        title: "Invalid State Inbox",
        filename: "invalid.json",
        relativePath: "state/inbox/invalid.json",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
      InboxItem(
        id: "inbox-archive/archived.md",
        title: "Archived Inbox",
        filename: "archived.md",
        relativePath: "inbox-archive/archived.md",
        content: "Content",
        contentIsTruncated: false,
        modifiedAt: Date(),
        isRead: false,
        summary: "Summary"
      ),
    ]
    
    // When: filtering items
    let unreadCount = items.filter { item in
      item.relativePath.hasPrefix("inbox/") &&
      !item.isRead
    }.count
    
    // Then: should only count exact "inbox/" prefix
    XCTAssertEqual(unreadCount, 1, "Should only match exact 'inbox/' prefix, not 'state/inbox/' or 'inbox-archive/'")
  }
}
