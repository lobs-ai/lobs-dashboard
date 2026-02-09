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
    
    /// IDs of reviewed text dumps
    var reviewedTextDumpIds: [String]
    
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
        autoRefreshEnabled: Bool = true,
        autoRefreshIntervalSeconds: Int = 30,
        readInboxItemIds: [String] = [],
        lastSeenThreadCounts: [String: Int] = [:],
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
        self.autoRefreshEnabled = autoRefreshEnabled
        self.autoRefreshIntervalSeconds = autoRefreshIntervalSeconds
        self.readInboxItemIds = readInboxItemIds
        self.lastSeenThreadCounts = lastSeenThreadCounts
        self.reviewedTextDumpIds = reviewedTextDumpIds
    }
}
