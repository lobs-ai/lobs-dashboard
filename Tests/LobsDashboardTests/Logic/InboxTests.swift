import XCTest
@testable import LobsDashboard

@MainActor
final class InboxTests: XCTestCase {
  
  func testMarkAllInboxItemsAsRead_marksUnreadItemsAsRead() {
    // Given: AppViewModel with some unread inbox items
    let vm = AppViewModel()
    
    let item1 = InboxItem(
      id: "item1",
      title: "Test Item 1",
      filename: "test1.md",
      relativePath: "inbox/test1.md",
      summary: "First test item",
      content: "Content 1",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let item2 = InboxItem(
      id: "item2",
      title: "Test Item 2",
      filename: "test2.md",
      relativePath: "inbox/test2.md",
      summary: "Second test item",
      content: "Content 2",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    let item3 = InboxItem(
      id: "item3",
      title: "Test Item 3",
      filename: "test3.md",
      relativePath: "inbox/test3.md",
      summary: "Third test item (already read)",
      content: "Content 3",
      modifiedAt: Date(),
      isRead: true,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [item1, item2, item3]
    vm.readItemIds.insert("item3") // item3 already read
    
    // Verify initial state
    XCTAssertEqual(vm.unreadInboxCount, 2, "Should have 2 unread items initially")
    XCTAssertFalse(vm.inboxItems[0].isRead, "Item 1 should be unread")
    XCTAssertFalse(vm.inboxItems[1].isRead, "Item 2 should be unread")
    XCTAssertTrue(vm.inboxItems[2].isRead, "Item 3 should be read")
    
    // When: Mark all as read
    vm.markAllInboxItemsAsRead()
    
    // Then: All items should be marked as read
    XCTAssertEqual(vm.unreadInboxCount, 0, "Should have 0 unread items after marking all as read")
    XCTAssertTrue(vm.inboxItems[0].isRead, "Item 1 should be read")
    XCTAssertTrue(vm.inboxItems[1].isRead, "Item 2 should be read")
    XCTAssertTrue(vm.inboxItems[2].isRead, "Item 3 should still be read")
    XCTAssertTrue(vm.readItemIds.contains("item1"), "readItemIds should contain item1")
    XCTAssertTrue(vm.readItemIds.contains("item2"), "readItemIds should contain item2")
    XCTAssertTrue(vm.readItemIds.contains("item3"), "readItemIds should contain item3")
  }
  
  func testMarkAllInboxItemsAsRead_withEmptyInbox() {
    // Given: AppViewModel with no inbox items
    let vm = AppViewModel()
    vm.inboxItems = []
    
    // When: Mark all as read
    vm.markAllInboxItemsAsRead()
    
    // Then: No errors should occur
    XCTAssertEqual(vm.unreadInboxCount, 0, "Should have 0 unread items")
    XCTAssertTrue(vm.readItemIds.isEmpty, "readItemIds should be empty")
  }
  
  func testMarkAllInboxItemsAsRead_withAllItemsAlreadyRead() {
    // Given: AppViewModel with all items already read
    let vm = AppViewModel()
    
    let item1 = InboxItem(
      id: "item1",
      title: "Test Item 1",
      filename: "test1.md",
      relativePath: "inbox/test1.md",
      summary: "First test item",
      content: "Content 1",
      modifiedAt: Date(),
      isRead: true,
      contentIsTruncated: false
    )
    
    let item2 = InboxItem(
      id: "item2",
      title: "Test Item 2",
      filename: "test2.md",
      relativePath: "inbox/test2.md",
      summary: "Second test item",
      content: "Content 2",
      modifiedAt: Date(),
      isRead: true,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [item1, item2]
    vm.readItemIds = ["item1", "item2"]
    
    let initialReadIdsCount = vm.readItemIds.count
    
    // When: Mark all as read
    vm.markAllInboxItemsAsRead()
    
    // Then: All items should still be read, no duplicates
    XCTAssertEqual(vm.unreadInboxCount, 0, "Should have 0 unread items")
    XCTAssertTrue(vm.inboxItems[0].isRead, "Item 1 should be read")
    XCTAssertTrue(vm.inboxItems[1].isRead, "Item 2 should be read")
    XCTAssertEqual(vm.readItemIds.count, initialReadIdsCount, "readItemIds count should not change")
  }
  
  func testMarkAllInboxItemsAsRead_updatesLastSeenThreadCounts() {
    // Given: AppViewModel with unread items and threads
    let vm = AppViewModel()
    
    let item1 = InboxItem(
      id: "item1",
      title: "Test Item 1",
      filename: "test1.md",
      relativePath: "inbox/test1.md",
      summary: "First test item",
      content: "Content 1",
      modifiedAt: Date(),
      isRead: false,
      contentIsTruncated: false
    )
    
    vm.inboxItems = [item1]
    
    // Add a thread for item1
    let thread = InboxThread(
      docId: "item1",
      messages: [
        InboxThreadMessage(id: "msg1", author: "test", text: "Hello", createdAt: Date())
      ],
      triageStatus: .needsResponse
    )
    vm.inboxThreadsByDocId["item1"] = thread
    
    // When: Mark all as read
    vm.markAllInboxItemsAsRead()
    
    // Then: lastSeenThreadCounts should be updated
    XCTAssertNotNil(vm.lastSeenThreadCounts["item1"], "lastSeenThreadCounts should have entry for item1")
    XCTAssertEqual(vm.lastSeenThreadCounts["item1"], 1, "lastSeenThreadCounts should match thread message count")
  }
}
