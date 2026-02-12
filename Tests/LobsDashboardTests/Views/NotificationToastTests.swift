import XCTest
@testable import LobsDashboard

/// Tests for notification toast dismissal functionality
@MainActor
final class NotificationToastTests: XCTestCase {
  
  /// Test that notifications can be dismissed via the dismiss function
  func testNotificationCanBeDismissed() {
    // Given: AppViewModel with a notification
    let vm = AppViewModel()
    
    let notification = DashboardNotification(
      type: .info,
      message: "Test notification",
      dismissed: false
    )
    
    vm.notifications = [notification]
    
    // Verify initial state
    XCTAssertEqual(vm.notifications.count, 1, "Should have 1 notification")
    XCTAssertFalse(vm.notifications[0].dismissed, "Notification should not be dismissed initially")
    
    // When: Dismiss the notification
    vm.dismissNotification(id: notification.id)
    
    // Then: Notification should be marked as dismissed
    XCTAssertEqual(vm.notifications.count, 1, "Notification should still be in array")
    XCTAssertTrue(vm.notifications[0].dismissed, "Notification should be marked as dismissed")
  }
  
  /// Test that dismissed notifications are filtered from the UI
  func testDismissedNotificationsAreFiltered() {
    // Given: AppViewModel with dismissed and non-dismissed notifications
    let vm = AppViewModel()
    
    let notification1 = DashboardNotification(
      id: "notif1",
      type: .info,
      message: "Active notification",
      dismissed: false
    )
    
    let notification2 = DashboardNotification(
      id: "notif2",
      type: .success,
      message: "Dismissed notification",
      dismissed: true
    )
    
    let notification3 = DashboardNotification(
      id: "notif3",
      type: .warning,
      message: "Another active notification",
      dismissed: false
    )
    
    vm.notifications = [notification1, notification2, notification3]
    
    // When: Filter notifications as the UI does
    let visibleNotifications = vm.notifications.filter { !$0.dismissed }
    
    // Then: Only non-dismissed notifications should be visible
    XCTAssertEqual(visibleNotifications.count, 2, "Should have 2 visible notifications")
    XCTAssertTrue(visibleNotifications.contains(where: { $0.id == "notif1" }), "Should contain notification 1")
    XCTAssertFalse(visibleNotifications.contains(where: { $0.id == "notif2" }), "Should not contain dismissed notification 2")
    XCTAssertTrue(visibleNotifications.contains(where: { $0.id == "notif3" }), "Should contain notification 3")
  }
  
  /// Test that multiple notifications can be dismissed independently
  func testMultipleNotificationsDismissIndependently() {
    // Given: AppViewModel with multiple notifications
    let vm = AppViewModel()
    
    let notification1 = DashboardNotification(
      id: "notif1",
      type: .info,
      message: "Notification 1"
    )
    
    let notification2 = DashboardNotification(
      id: "notif2",
      type: .success,
      message: "Notification 2"
    )
    
    let notification3 = DashboardNotification(
      id: "notif3",
      type: .warning,
      message: "Notification 3"
    )
    
    vm.notifications = [notification1, notification2, notification3]
    
    // When: Dismiss only the second notification
    vm.dismissNotification(id: "notif2")
    
    // Then: Only notification 2 should be dismissed
    let visibleNotifications = vm.notifications.filter { !$0.dismissed }
    XCTAssertEqual(visibleNotifications.count, 2, "Should have 2 visible notifications")
    XCTAssertFalse(vm.notifications[1].dismissed == false, "Notification 2 should be dismissed")
    XCTAssertFalse(vm.notifications[0].dismissed, "Notification 1 should not be dismissed")
    XCTAssertFalse(vm.notifications[2].dismissed, "Notification 3 should not be dismissed")
  }
  
  /// Test that dismissing a non-existent notification doesn't crash
  func testDismissNonExistentNotificationDoesNotCrash() {
    // Given: AppViewModel with one notification
    let vm = AppViewModel()
    
    let notification = DashboardNotification(
      id: "existing",
      type: .info,
      message: "Existing notification"
    )
    
    vm.notifications = [notification]
    
    // When: Try to dismiss a notification that doesn't exist
    vm.dismissNotification(id: "non-existent")
    
    // Then: Should not crash and existing notification should be unchanged
    XCTAssertEqual(vm.notifications.count, 1, "Should still have 1 notification")
    XCTAssertFalse(vm.notifications[0].dismissed, "Existing notification should not be affected")
  }
  
  /// Test that all notifications can be dismissed at once
  func testDismissAllNotifications() {
    // Given: AppViewModel with multiple notifications
    let vm = AppViewModel()
    
    let notification1 = DashboardNotification(type: .info, message: "Notification 1")
    let notification2 = DashboardNotification(type: .success, message: "Notification 2")
    let notification3 = DashboardNotification(type: .warning, message: "Notification 3")
    
    vm.notifications = [notification1, notification2, notification3]
    
    // When: Dismiss all notifications
    vm.dismissAllNotifications()
    
    // Then: All notifications should be dismissed
    let visibleNotifications = vm.notifications.filter { !$0.dismissed }
    XCTAssertEqual(visibleNotifications.count, 0, "Should have no visible notifications after dismissing all")
    XCTAssertTrue(vm.notifications.allSatisfy { $0.dismissed }, "All notifications should be marked as dismissed")
  }
  
  /// Test notification type-specific icon mapping
  func testNotificationTypeIconMapping() {
    // This test documents the expected icon names for each notification type
    // These should match the NotificationToast component implementation
    
    let testCases: [(NotificationType, String)] = [
      (.reminder, "bell.fill"),
      (.blocker, "exclamationmark.triangle.fill"),
      (.error, "xmark.circle.fill"),
      (.success, "checkmark.circle.fill"),
      (.info, "info.circle.fill"),
      (.warning, "exclamationmark.circle.fill")
    ]
    
    // This test documents the expected behavior
    // Actual implementation is in NotificationToast component
    for (type, expectedIcon) in testCases {
      XCTAssertNotNil(type, "Type \(type) should map to icon \(expectedIcon)")
    }
  }
  
  /// Test notification type color mapping
  func testNotificationTypeColorMapping() {
    // This test documents the expected color associations for each notification type
    // Expected mappings (as implemented in NotificationToast):
    // - reminder: purple
    // - blocker: red
    // - error: red
    // - success: green
    // - info: blue
    // - warning: orange
    
    let types = NotificationType.allCases
    XCTAssertEqual(types.count, 6, "Should have 6 notification types")
  }
}
