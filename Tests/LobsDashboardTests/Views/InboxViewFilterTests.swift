import XCTest
import SwiftUI
@testable import LobsDashboard

/// Tests for InboxView filtering logic, specifically verifying that artifacts
/// are excluded from the inbox view while both inbox/ and state/inbox/ items are shown.
@MainActor
final class InboxViewFilterTests: XCTestCase {
  
  /// Test that artifacts are filtered out while inbox and state/inbox items are kept
  func testArtifactsAreFilteredOut() {
    // Given: AppViewModel with inbox items, state/inbox items, and artifacts
    let vm = AppViewModel()
    
    let inboxItem1 = InboxItem(
      id: "inbox/doc1.md",
      title: "Inbox Doc 1",
      filename: "doc1.md",
      relativePath: "inbox/doc1.md",
      summary: "This is an inbox item",
      content: "Inbox content 1",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let inboxItem2 = InboxItem(
      id: "inbox/doc2.md",
      title: "Inbox Doc 2",
      filename: "doc2.md",
      relativePath: "inbox/doc2.md",
      summary: "Another inbox item",
      content: "Inbox content 2",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let stateInboxItem = InboxItem(
      id: "state/inbox/suggestion1.json",
      title: "Suggestion 1",
      filename: "suggestion1.json",
      relativePath: "state/inbox/suggestion1.json",
      summary: "This is a state/inbox suggestion",
      content: "Suggestion content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let artifact1 = InboxItem(
      id: "artifacts/design1.md",
      title: "Design Doc 1",
      filename: "design1.md",
      relativePath: "artifacts/design1.md",
      summary: "This is an artifact",
      content: "Artifact content 1",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let artifact2 = InboxItem(
      id: "artifacts/spec2.md",
      title: "Spec Doc 2",
      filename: "spec2.md",
      relativePath: "artifacts/spec2.md",
      summary: "Another artifact",
      content: "Artifact content 2",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [inboxItem1, artifact1, stateInboxItem, inboxItem2, artifact2]
    
    // When: Filter using the same logic as InboxView
    // The InboxView filters items with: items.filter { !$0.relativePath.hasPrefix("artifacts/") }
    let filteredItems = vm.inboxItems.filter { !$0.relativePath.hasPrefix("artifacts/") }
    
    // Then: Inbox and state/inbox items should remain, artifacts should be excluded
    XCTAssertEqual(filteredItems.count, 3, "Should have 3 items after filtering (2 inbox + 1 state/inbox)")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "inbox/doc1.md" }), "Should contain inbox item 1")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "inbox/doc2.md" }), "Should contain inbox item 2")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "state/inbox/suggestion1.json" }), "Should contain state/inbox item")
    XCTAssertFalse(filteredItems.contains(where: { $0.id == "artifacts/design1.md" }), "Should not contain artifact 1")
    XCTAssertFalse(filteredItems.contains(where: { $0.id == "artifacts/spec2.md" }), "Should not contain artifact 2")
  }
  
  /// Test that only artifacts/ paths are filtered out, not other directories
  func testOnlyArtifactsPathIsFilteredOut() {
    // Given: AppViewModel with inbox items and items in various locations
    let vm = AppViewModel()
    
    let inboxItem = InboxItem(
      id: "inbox/doc.md",
      title: "Inbox Doc",
      filename: "doc.md",
      relativePath: "inbox/doc.md",
      summary: "Inbox item",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let stateInboxItem = InboxItem(
      id: "state/inbox/suggestion.json",
      title: "Suggestion",
      filename: "suggestion.json",
      relativePath: "state/inbox/suggestion.json",
      summary: "State inbox item",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let artifactItem = InboxItem(
      id: "artifacts/doc.md",
      title: "Artifact in artifacts/",
      filename: "doc.md",
      relativePath: "artifacts/doc.md",
      summary: "Artifact",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [inboxItem, stateInboxItem, artifactItem]
    
    // When: Filter using the same logic as InboxView
    let filteredItems = vm.inboxItems.filter { !$0.relativePath.hasPrefix("artifacts/") }
    
    // Then: Only artifacts/ should be filtered out
    XCTAssertEqual(filteredItems.count, 2, "Should have 2 items (inbox + state/inbox)")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "inbox/doc.md" }), "Should contain inbox item")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "state/inbox/suggestion.json" }), "Should contain state/inbox item")
    XCTAssertFalse(filteredItems.contains(where: { $0.id == "artifacts/doc.md" }), "Should not contain artifact")
  }
  
  /// Test that filtering works correctly when there are only artifacts
  func testOnlyArtifactsResultsInEmptyList() {
    // Given: AppViewModel with only artifacts, no inbox items
    let vm = AppViewModel()
    
    let artifact1 = InboxItem(
      id: "artifacts/design.md",
      title: "Design Doc",
      filename: "design.md",
      relativePath: "artifacts/design.md",
      summary: "Design artifact",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let artifact2 = InboxItem(
      id: "artifacts/spec.md",
      title: "Spec Doc",
      filename: "spec.md",
      relativePath: "artifacts/spec.md",
      summary: "Spec artifact",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [artifact1, artifact2]
    
    // When: Filter using the same logic as InboxView
    let filteredItems = vm.inboxItems.filter { !$0.relativePath.hasPrefix("artifacts/") }
    
    // Then: No items should be shown
    XCTAssertEqual(filteredItems.count, 0, "Should have 0 items when only artifacts exist")
  }
  
  /// Test that filtering works correctly when there are only inbox items
  func testOnlyInboxItemsResultsInFullList() {
    // Given: AppViewModel with inbox and state/inbox items, no artifacts
    let vm = AppViewModel()
    
    let inboxItem1 = InboxItem(
      id: "inbox/doc1.md",
      title: "Inbox Doc 1",
      filename: "doc1.md",
      relativePath: "inbox/doc1.md",
      summary: "Inbox item 1",
      content: "Content 1",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let inboxItem2 = InboxItem(
      id: "inbox/doc2.md",
      title: "Inbox Doc 2",
      filename: "doc2.md",
      relativePath: "inbox/doc2.md",
      summary: "Inbox item 2",
      content: "Content 2",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let stateInboxItem = InboxItem(
      id: "state/inbox/suggestion.json",
      title: "Suggestion",
      filename: "suggestion.json",
      relativePath: "state/inbox/suggestion.json",
      summary: "State inbox item",
      content: "Suggestion content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [inboxItem1, inboxItem2, stateInboxItem]
    
    // When: Filter using the same logic as InboxView
    let filteredItems = vm.inboxItems.filter { !$0.relativePath.hasPrefix("artifacts/") }
    
    // Then: All items should be shown
    XCTAssertEqual(filteredItems.count, 3, "Should have all 3 inbox items (2 inbox + 1 state/inbox)")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "inbox/doc1.md" }), "Should contain inbox item 1")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "inbox/doc2.md" }), "Should contain inbox item 2")
    XCTAssertTrue(filteredItems.contains(where: { $0.id == "state/inbox/suggestion.json" }), "Should contain state/inbox item")
  }
  
  /// Test that artifact filtering preserves the order of inbox items
  func testArtifactFilteringPreservesOrder() {
    // Given: AppViewModel with mixed inbox items, state/inbox items, and artifacts
    let vm = AppViewModel()
    
    let inboxItem1 = InboxItem(
      id: "inbox/a.md",
      title: "A",
      filename: "a.md",
      relativePath: "inbox/a.md",
      summary: "Item A",
      content: "Content A",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let artifact1 = InboxItem(
      id: "artifacts/b.md",
      title: "B",
      filename: "b.md",
      relativePath: "artifacts/b.md",
      summary: "Artifact B",
      content: "Content B",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let stateInboxItem = InboxItem(
      id: "state/inbox/c.json",
      title: "C",
      filename: "c.json",
      relativePath: "state/inbox/c.json",
      summary: "State inbox item C",
      content: "Content C",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let artifact2 = InboxItem(
      id: "artifacts/d.md",
      title: "D",
      filename: "d.md",
      relativePath: "artifacts/d.md",
      summary: "Artifact D",
      content: "Content D",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let inboxItem2 = InboxItem(
      id: "inbox/e.md",
      title: "E",
      filename: "e.md",
      relativePath: "inbox/e.md",
      summary: "Item E",
      content: "Content E",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [inboxItem1, artifact1, stateInboxItem, artifact2, inboxItem2]
    
    // When: Filter using the same logic as InboxView
    let filteredItems = vm.inboxItems.filter { !$0.relativePath.hasPrefix("artifacts/") }
    
    // Then: Non-artifact items should be in their original order
    XCTAssertEqual(filteredItems.count, 3, "Should have 3 non-artifact items")
    XCTAssertEqual(filteredItems[0].id, "inbox/a.md", "First item should be A")
    XCTAssertEqual(filteredItems[1].id, "state/inbox/c.json", "Second item should be C")
    XCTAssertEqual(filteredItems[2].id, "inbox/e.md", "Third item should be E")
  }
  
  /// Test that unread count correctly excludes artifacts
  func testUnreadCountExcludesArtifacts() {
    // Given: AppViewModel with unread inbox items, state/inbox items, and artifacts
    let vm = AppViewModel()
    
    let unreadInboxItem = InboxItem(
      id: "inbox/doc1.md",
      title: "Unread Inbox Doc",
      filename: "doc1.md",
      relativePath: "inbox/doc1.md",
      summary: "Unread inbox item",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let readInboxItem = InboxItem(
      id: "inbox/doc2.md",
      title: "Read Inbox Doc",
      filename: "doc2.md",
      relativePath: "inbox/doc2.md",
      summary: "Read inbox item",
      content: "Content",
      modifiedAt: Date(),
      isRead: true,
      contentIsTruncated: false
    )
    
    let unreadStateInboxItem = InboxItem(
      id: "state/inbox/suggestion.json",
      title: "Unread Suggestion",
      filename: "suggestion.json",
      relativePath: "state/inbox/suggestion.json",
      summary: "Unread state/inbox item",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let unreadArtifact = InboxItem(
      id: "artifacts/design.md",
      title: "Unread Artifact",
      filename: "design.md",
      relativePath: "artifacts/design.md",
      summary: "Unread artifact",
      content: "Content",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [unreadInboxItem, readInboxItem, unreadStateInboxItem, unreadArtifact]
    vm.readItemIds.insert("inbox/doc2.md")
    
    // When: Calculate unread count (should match unreadInboxCount implementation)
    let unreadCount = vm.unreadInboxCount
    
    // Then: Should count only unread non-artifact items (inbox + state/inbox)
    // unreadInboxCount filters: !item.relativePath.hasPrefix("artifacts/") && !item.isRead
    XCTAssertEqual(unreadCount, 2, "Should count 2 unread items (inbox + state/inbox, excluding artifact)")
    
    // Verify the same logic when filtering in the view:
    let visibleUnreadItems = vm.inboxItems
      .filter { !$0.relativePath.hasPrefix("artifacts/") }
      .filter { !$0.isRead }
    XCTAssertEqual(visibleUnreadItems.count, 2, "Should have 2 unread items visible in the view")
  }
  
  /// Test that state/inbox items are correctly identified as inbox items (not artifacts) in badge logic
  func testStateInboxItemsAreNotLabeledAsArtifacts() {
    // This test documents the badge logic behavior - verifying that state/inbox items
    // are correctly identified as inbox items for badge display purposes
    
    // Given: Various item paths
    let inboxPath = "inbox/doc.md"
    let stateInboxPath = "state/inbox/suggestion.json"
    let artifactPath = "artifacts/design.md"
    
    // When: Apply the badge logic (isInbox check)
    let inboxIsInbox = inboxPath.hasPrefix("inbox/") || inboxPath.hasPrefix("state/inbox/")
    let stateInboxIsInbox = stateInboxPath.hasPrefix("inbox/") || stateInboxPath.hasPrefix("state/inbox/")
    let artifactIsInbox = artifactPath.hasPrefix("inbox/") || artifactPath.hasPrefix("state/inbox/")
    
    // Then: Both inbox/ and state/inbox/ should be identified as inbox items
    XCTAssertTrue(inboxIsInbox, "inbox/ items should show Inbox badge")
    XCTAssertTrue(stateInboxIsInbox, "state/inbox/ items should show Inbox badge")
    XCTAssertFalse(artifactIsInbox, "artifacts/ items should show Artifact badge")
  }
}
