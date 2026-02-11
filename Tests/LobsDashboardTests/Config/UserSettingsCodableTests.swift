import XCTest
@testable import LobsDashboard

final class UserSettingsCodableTests: XCTestCase {

    func testDefaultValues() {
        let settings = UserSettings()
        XCTAssertEqual(settings.ownerFilter, "all")
        XCTAssertEqual(settings.wipLimitActive, 6)
        XCTAssertEqual(settings.completedShowRecent, 30)
        XCTAssertTrue(settings.autoArchiveCompleted)
        XCTAssertEqual(settings.archiveCompletedAfterDays, 7)
        XCTAssertTrue(settings.autoArchiveReadInbox)
        XCTAssertEqual(settings.archiveReadInboxAfterDays, 7)
        XCTAssertEqual(settings.appearanceMode, 0)
        XCTAssertEqual(settings.quickCaptureHotkeyMode, 1)
        XCTAssertEqual(settings.selectedProjectId, "default")
        XCTAssertTrue(settings.menuBarWidgetEnabled)
        XCTAssertFalse(settings.firstTaskWalkthroughComplete)
        XCTAssertTrue(settings.autoRefreshEnabled)
        XCTAssertEqual(settings.autoRefreshIntervalSeconds, 30)
    }

    func testDecodeEmptyJSON() throws {
        let json = "{}".data(using: .utf8)!
        let settings = try JSONDecoder().decode(UserSettings.self, from: json)

        // Should get all defaults
        XCTAssertEqual(settings.ownerFilter, "all")
        XCTAssertEqual(settings.wipLimitActive, 6)
    }

    func testDecodePartialJSON() throws {
        let json = """
        {
          "ownerFilter": "lobs",
          "wipLimitActive": 10
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(UserSettings.self, from: json)
        XCTAssertEqual(settings.ownerFilter, "lobs")
        XCTAssertEqual(settings.wipLimitActive, 10)
        // Others should be defaults
        XCTAssertEqual(settings.completedShowRecent, 30)
    }

    func testFullRoundTrip() throws {
        let original = UserSettings(
            ownerFilter: "rafe",
            wipLimitActive: 5,
            completedShowRecent: 50,
            autoArchiveCompleted: false,
            readInboxItemIds: ["item1", "item2"],
            lastSeenThreadCounts: ["doc1": 3, "doc2": 5]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UserSettings.self, from: data)

        XCTAssertEqual(decoded.ownerFilter, original.ownerFilter)
        XCTAssertEqual(decoded.wipLimitActive, original.wipLimitActive)
        XCTAssertEqual(decoded.completedShowRecent, original.completedShowRecent)
        XCTAssertEqual(decoded.autoArchiveCompleted, original.autoArchiveCompleted)
        XCTAssertEqual(decoded.readInboxItemIds, original.readInboxItemIds)
        XCTAssertEqual(decoded.lastSeenThreadCounts, original.lastSeenThreadCounts)
    }

    func testMissingFieldsGetDefaults() throws {
        // Simulate old config file missing new fields
        let json = """
        {
          "ownerFilter": "all"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(UserSettings.self, from: json)
        // New fields should have defaults
        XCTAssertEqual(settings.menuBarWidgetEnabled, true)
        XCTAssertEqual(settings.autoRefreshIntervalSeconds, 30)
    }
}
