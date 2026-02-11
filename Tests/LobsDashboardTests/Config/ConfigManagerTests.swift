import XCTest
@testable import LobsDashboard

final class ConfigManagerTests: XCTestCase {

    func testMergeSettings_PreferExistingNonDefaults() {
        let existing = UserSettings(
            ownerFilter: "lobs",  // Non-default
            wipLimitActive: 10
        )
        let migrated = UserSettings(
            ownerFilter: "rafe",  // Different value
            wipLimitActive: 8
        )

        let merged = ConfigManager.mergeSettings(existing: existing, migrated: migrated)

        // Should keep existing non-default
        XCTAssertEqual(merged.ownerFilter, "lobs")
    }

    func testMergeSettings_UseMigratedWhenExistingIsDefault() {
        let existing = UserSettings(
            ownerFilter: "all",  // Default value
            selectedProjectId: "default"  // Default value
        )
        let migrated = UserSettings(
            ownerFilter: "lobs",  // Non-default
            selectedProjectId: "project-1"  // Non-default
        )

        let merged = ConfigManager.mergeSettings(existing: existing, migrated: migrated)

        // Should use migrated values since existing are defaults
        XCTAssertEqual(merged.ownerFilter, "lobs")
        XCTAssertEqual(merged.selectedProjectId, "project-1")
    }

    func testMergeSettings_UnionArrays() {
        let existing = UserSettings(readInboxItemIds: ["item1", "item2"])
        let migrated = UserSettings(readInboxItemIds: ["item2", "item3"])

        let merged = ConfigManager.mergeSettings(existing: existing, migrated: migrated)

        // Should union the arrays
        XCTAssertEqual(Set(merged.readInboxItemIds), Set(["item1", "item2", "item3"]))
    }

    func testMergeSettings_MaxThreadCounts() {
        let existing = UserSettings(lastSeenThreadCounts: ["doc1": 5, "doc2": 10])
        let migrated = UserSettings(lastSeenThreadCounts: ["doc1": 8, "doc3": 3])

        let merged = ConfigManager.mergeSettings(existing: existing, migrated: migrated)

        // Should use max value for overlapping keys
        XCTAssertEqual(merged.lastSeenThreadCounts["doc1"], 8)  // max(5, 8)
        XCTAssertEqual(merged.lastSeenThreadCounts["doc2"], 10)  // only in existing
        XCTAssertEqual(merged.lastSeenThreadCounts["doc3"], 3)   // only in migrated
    }
}
