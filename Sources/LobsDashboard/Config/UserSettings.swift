import Foundation

/// User-specific settings and preferences
/// Stored locally in ~/.lobs/config.json (local-only settings)
/// Eventually some may sync via control repo state/settings.json
struct UserSettings: Codable {
    // MARK: - Kanban Preferences

    /// Selected owner filter ("all", "lobs", "rafe", etc.)
    var ownerFilter: String

    /// WIP limit for active tasks
    var wipLimitActive: Int

    /// Number of recent completed tasks to show
    var completedShowRecent: Int

    /// Whether to auto-archive completed tasks
    var autoArchiveCompleted: Bool

    /// Days before archiving completed tasks
    var archiveCompletedAfterDays: Int

    /// Whether to auto-archive read inbox items
    var autoArchiveReadInbox: Bool

    /// Days before archiving read inbox items
    var archiveReadInboxAfterDays: Int

    // MARK: - UI Preferences

    /// Appearance mode: 0 = System, 1 = Light, 2 = Dark
    var appearanceMode: Int

    /// Quick capture hotkey mode: 0 = ⌘⇧Space, 1 = ⌥Space
    var quickCaptureHotkeyMode: Int

    /// Currently selected project ID
    var selectedProjectId: String

    /// Whether to show the menu bar widget for ambient task awareness
    var menuBarWidgetEnabled: Bool

    // MARK: - Auto-refresh

    /// Whether auto-refresh is enabled
    var autoRefreshEnabled: Bool

    /// Auto-refresh interval in seconds
    var autoRefreshIntervalSeconds: Int

    // MARK: - Read State

    /// IDs of read inbox items
    var readInboxItemIds: [String]

    /// Last-seen thread message counts by doc ID
    var lastSeenThreadCounts: [String: Int]

    /// Timestamp of last local update to inbox read-state.
    /// Used to prevent older repo state from overwriting newer local state.
    var inboxReadStateUpdatedAt: Date?

    /// IDs of reviewed text dumps
    var reviewedTextDumpIds: [String]

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case ownerFilter
        case wipLimitActive
        case completedShowRecent
        case autoArchiveCompleted
        case archiveCompletedAfterDays
        case autoArchiveReadInbox
        case archiveReadInboxAfterDays
        case appearanceMode
        case quickCaptureHotkeyMode
        case selectedProjectId
        case menuBarWidgetEnabled
        case autoRefreshEnabled
        case autoRefreshIntervalSeconds
        case readInboxItemIds
        case lastSeenThreadCounts
        case inboxReadStateUpdatedAt
        case reviewedTextDumpIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        ownerFilter = try c.decodeIfPresent(String.self, forKey: .ownerFilter) ?? "all"
        wipLimitActive = try c.decodeIfPresent(Int.self, forKey: .wipLimitActive) ?? 6
        completedShowRecent = try c.decodeIfPresent(Int.self, forKey: .completedShowRecent) ?? 30

        autoArchiveCompleted = try c.decodeIfPresent(Bool.self, forKey: .autoArchiveCompleted) ?? true
        archiveCompletedAfterDays = try c.decodeIfPresent(Int.self, forKey: .archiveCompletedAfterDays) ?? 7

        autoArchiveReadInbox = try c.decodeIfPresent(Bool.self, forKey: .autoArchiveReadInbox) ?? true
        archiveReadInboxAfterDays = try c.decodeIfPresent(Int.self, forKey: .archiveReadInboxAfterDays) ?? 7

        appearanceMode = try c.decodeIfPresent(Int.self, forKey: .appearanceMode) ?? 0
        quickCaptureHotkeyMode = try c.decodeIfPresent(Int.self, forKey: .quickCaptureHotkeyMode) ?? 1

        selectedProjectId = try c.decodeIfPresent(String.self, forKey: .selectedProjectId) ?? "default"
        menuBarWidgetEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarWidgetEnabled) ?? true

        autoRefreshEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? true
        autoRefreshIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .autoRefreshIntervalSeconds) ?? 30

        readInboxItemIds = try c.decodeIfPresent([String].self, forKey: .readInboxItemIds) ?? []
        lastSeenThreadCounts = try c.decodeIfPresent([String: Int].self, forKey: .lastSeenThreadCounts) ?? [:]
        inboxReadStateUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .inboxReadStateUpdatedAt)
        reviewedTextDumpIds = try c.decodeIfPresent([String].self, forKey: .reviewedTextDumpIds) ?? []
    }

    // MARK: - Defaults

    init(
        ownerFilter: String = "all",
        wipLimitActive: Int = 6,
        completedShowRecent: Int = 30,
        autoArchiveCompleted: Bool = true,
        archiveCompletedAfterDays: Int = 7,
        autoArchiveReadInbox: Bool = true,
        archiveReadInboxAfterDays: Int = 7,
        appearanceMode: Int = 0,
        quickCaptureHotkeyMode: Int = 1,
        selectedProjectId: String = "default",
        menuBarWidgetEnabled: Bool = true,
        autoRefreshEnabled: Bool = true,
        autoRefreshIntervalSeconds: Int = 30,
        readInboxItemIds: [String] = [],
        lastSeenThreadCounts: [String: Int] = [:],
        inboxReadStateUpdatedAt: Date? = nil,
        reviewedTextDumpIds: [String] = []
    ) {
        self.ownerFilter = ownerFilter
        self.wipLimitActive = wipLimitActive
        self.completedShowRecent = completedShowRecent
        self.autoArchiveCompleted = autoArchiveCompleted
        self.archiveCompletedAfterDays = archiveCompletedAfterDays
        self.autoArchiveReadInbox = autoArchiveReadInbox
        self.archiveReadInboxAfterDays = archiveReadInboxAfterDays
        self.appearanceMode = appearanceMode
        self.quickCaptureHotkeyMode = quickCaptureHotkeyMode
        self.selectedProjectId = selectedProjectId
        self.menuBarWidgetEnabled = menuBarWidgetEnabled
        self.autoRefreshEnabled = autoRefreshEnabled
        self.autoRefreshIntervalSeconds = autoRefreshIntervalSeconds
        self.readInboxItemIds = readInboxItemIds
        self.lastSeenThreadCounts = lastSeenThreadCounts
        self.inboxReadStateUpdatedAt = inboxReadStateUpdatedAt
        self.reviewedTextDumpIds = reviewedTextDumpIds
    }
}
