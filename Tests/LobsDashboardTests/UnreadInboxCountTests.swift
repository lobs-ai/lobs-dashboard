import XCTest
@testable import LobsDashboard

/// Tests that unreadInboxCount only counts actual inbox items, not artifacts
final class UnreadInboxCountTests: XCTestCase {
  
  func testUnreadCountExcludesArtifacts() {
    let vm = AppViewModel()
    
    let inboxItem = InboxItem(
      id: "inbox/test.md",
      title: "Inbox Item",
      filename: "test.md",
      relativePath: "inbox/test.md",
      content: "",
      contentIsTruncated: false,
      modifiedAt: Date(),
      isRead: false,
      summary: ""
    )
    
    let artifact = InboxItem(
      id: "artifacts/thing.md",
      title: "Artifact",
      filename: "thing.md",
      relativePath: "artifacts/thing.md",
      content: "",
      contentIsTruncated: false,
      modifiedAt: Date(),
      isRead: false,
      summary: ""
    )
    
    vm.inboxItems = [inboxItem, artifact]
    
    // Only the inbox item should count as unread, not the artifact
    XCTAssertEqual(vm.unreadInboxCount, 1, "Artifacts should not be counted as unread inbox items")
  }
  
  func testUnreadCountIncludesOnlyInboxPrefix() {
    let vm = AppViewModel()
    
    let items = [
      InboxItem(id: "1", title: "A", filename: "a.md", relativePath: "inbox/a.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: false, summary: ""),
      InboxItem(id: "2", title: "B", filename: "b.md", relativePath: "inbox/b.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: false, summary: ""),
      InboxItem(id: "3", title: "C", filename: "c.md", relativePath: "artifacts/c.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: false, summary: ""),
      InboxItem(id: "4", title: "D", filename: "d.md", relativePath: "state/inbox/d.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: false, summary: ""),
    ]
    
    vm.inboxItems = items
    
    // Only items 1 and 2 have relativePath starting with "inbox/"
    XCTAssertEqual(vm.unreadInboxCount, 2)
  }
  
  func testReadInboxItemsNotCounted() {
    let vm = AppViewModel()
    
    let readItem = InboxItem(id: "1", title: "Read", filename: "r.md", relativePath: "inbox/r.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: true, summary: "")
    let unreadItem = InboxItem(id: "2", title: "Unread", filename: "u.md", relativePath: "inbox/u.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: false, summary: "")
    
    vm.inboxItems = [readItem, unreadItem]
    
    XCTAssertEqual(vm.unreadInboxCount, 1, "Read items should not be counted")
  }
  
  func testEmptyInboxReturnsZero() {
    let vm = AppViewModel()
    vm.inboxItems = []
    XCTAssertEqual(vm.unreadInboxCount, 0)
  }
  
  func testAllReadReturnsZero() {
    let vm = AppViewModel()
    vm.inboxItems = [
      InboxItem(id: "1", title: "A", filename: "a.md", relativePath: "inbox/a.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: true, summary: ""),
    ]
    XCTAssertEqual(vm.unreadInboxCount, 0)
  }
  
  func testReadArtifactNotCounted() {
    let vm = AppViewModel()
    // Even if an artifact is unread, it should not count
    vm.inboxItems = [
      InboxItem(id: "1", title: "A", filename: "a.md", relativePath: "artifacts/a.md", content: "", contentIsTruncated: false, modifiedAt: Date(), isRead: false, summary: ""),
    ]
    XCTAssertEqual(vm.unreadInboxCount, 0, "Unread artifacts should never count towards inbox badge")
  }
}
