import XCTest
@testable import LobsDashboard

final class NotificationTypeTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(NotificationType.reminder.displayName, "Reminder")
        XCTAssertEqual(NotificationType.blocker.displayName, "Blocker")
        XCTAssertEqual(NotificationType.error.displayName, "Error")
        XCTAssertEqual(NotificationType.success.displayName, "Success")
        XCTAssertEqual(NotificationType.info.displayName, "Info")
        XCTAssertEqual(NotificationType.warning.displayName, "Warning")
    }

    func testIconNames() {
        XCTAssertEqual(NotificationType.reminder.iconName, "bell.fill")
        XCTAssertEqual(NotificationType.blocker.iconName, "hand.raised.fill")
        XCTAssertEqual(NotificationType.error.iconName, "xmark.circle.fill")
        XCTAssertEqual(NotificationType.success.iconName, "checkmark.circle.fill")
    }

    func testPriorityRouting() {
        XCTAssertEqual(NotificationType.reminder.priority, .high)
        XCTAssertEqual(NotificationType.blocker.priority, .high)
        XCTAssertEqual(NotificationType.error.priority, .high)
        XCTAssertEqual(NotificationType.warning.priority, .medium)
        XCTAssertEqual(NotificationType.success.priority, .low)
        XCTAssertEqual(NotificationType.info.priority, .low)
    }

    func testDefaultPreferences() {
        let prefs = NotificationPreferences.default

        // All types should be enabled by default
        XCTAssertTrue(prefs.enabledTypes.contains("reminder"))
        XCTAssertTrue(prefs.enabledTypes.contains("error"))
        XCTAssertTrue(prefs.enabledTypes.contains("success"))

        XCTAssertTrue(prefs.batchLowPriority)
        XCTAssertEqual(prefs.batchIntervalSeconds, 30)
    }
}
