import AppKit
import Foundation
import SwiftUI
import UserNotifications

enum GitHubCLIError: Error, LocalizedError {
  case commandFailed(stderr: String)
  case parseError(output: String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let stderr):
      return "gh command failed: \(stderr)"
    case .parseError(let output):
      return "Failed to parse issue number from gh output: \(output)"
    }
  }
}

// MARK: - Git Rebase Recovery

enum RebaseState {
  case none
  /// A rebase is in progress. If `conflictFiles` is non-empty, it likely needs resolution.
  case inProgress(conflictFiles: [String])
  /// A rebase is in progress but we couldn't reliably determine conflict state.
  case needsResolution
}

@MainActor
final class AppViewModel: ObservableObject {
  @Published private(set) var repoPath: String = ""

  nonisolated private static func decodingPathString(_ codingPath: [CodingKey]) -> String {
    if codingPath.isEmpty { return "<root>" }
    return codingPath.map { key in
      if let index = key.intValue { return "[\(index)]" }
      return key.stringValue
    }.joined(separator: ".")
  }

  nonisolated private static func describeLoadError(_ error: Error) -> String {
    if let decodingError = error as? DecodingError {
      switch decodingError {
      case .typeMismatch(let type, let context):
        return "typeMismatch(\(type)) at \(decodingPathString(context.codingPath)): \(context.debugDescription)"
      case .valueNotFound(let type, let context):
        return "valueNotFound(\(type)) at \(decodingPathString(context.codingPath)): \(context.debugDescription)"
      case .keyNotFound(let key, let context):
        return "keyNotFound(\(key.stringValue)) at \(decodingPathString(context.codingPath)): \(context.debugDescription)"
      case .dataCorrupted(let context):
        return "dataCorrupted at \(decodingPathString(context.codingPath)): \(context.debugDescription)"
      @unknown default:
        return "unknownDecodingError: \(decodingError.localizedDescription)"
      }
    }
    return error.localizedDescription
  }
  
  /// Current application configuration (includes user settings)
  @Published var config: AppConfig?
  
  /// API service for communicating with lobs-server
  var api: APIService
  var apiService: APIService? { api }

  /// Compatibility adapter for legacy call sites that still reference `cache`.
  @MainActor
  private struct TaskCacheAdapter {
    unowned let vm: AppViewModel

    var tasks: [DashboardTask] { vm.tasks }

    func updateTask(_ taskId: String, update: (inout DashboardTask) -> Void) {
      guard let idx = vm.tasks.firstIndex(where: { $0.id == taskId }) else { return }
      var task = vm.tasks[idx]
      update(&task)
      vm.tasks[idx] = task
    }

    func removeTask(_ taskId: String) {
      vm.tasks.removeAll { $0.id == taskId }
    }

    func invalidateTasks() {
      // No-op in API mode; data is already kept in-memory and refreshed by polling.
    }

    func getResearchDoc(_ projectId: String) -> String? {
      vm.researchDocContent
    }

    func getResearchSources(_ projectId: String) -> [ResearchSource] {
      vm.researchSources
    }

    func getResearchRequests(_ projectId: String) -> [ResearchRequest] {
      vm.researchRequests.filter { $0.projectId == projectId }
    }

    func getTrackerItems(_ projectId: String) -> [TrackerItem] {
      vm.trackerItems.filter { $0.projectId == projectId }
    }
  }

  private var cache: TaskCacheAdapter { TaskCacheAdapter(vm: self) }

  @MainActor
  private final class PollingManagerCompat {
    func startResearchPolling(projectId: String) {}
    func stopResearchPolling(projectId: String) {}
    func startTrackerPolling(projectId: String) {}
    func stopTrackerPolling(projectId: String) {}
    func refreshStaleData() async {}
  }

  private let pollingManager = PollingManagerCompat()

  private var inboxReadItemIds: Set<String> { readItemIds }
  private var inboxLastSeenThreadCounts: [String: Int] { lastSeenThreadCounts }
  
  /// Helper to access settings from config
  private var settings: UserSettings {
    get { config?.settings ?? UserSettings() }
    set {
      var updatedConfig = config ?? AppConfig()
      updatedConfig.settings = newValue
      config = updatedConfig
      saveConfig()
    }
  }
  
  /// Save config to disk
  private func saveConfig() {
    guard let config = config else { return }
    do {
      try ConfigManager.save(config)
    } catch {
      print("⚠️ Failed to save config: \(error)")
    }
  }

  // MARK: - User preference helpers

  var menuBarWidgetEnabled: Bool {
    get { settings.menuBarWidgetEnabled }
    set {
      var s = settings
      s.menuBarWidgetEnabled = newValue
      settings = s
    }
  }

  var firstTaskWalkthroughComplete: Bool {
    get { settings.firstTaskWalkthroughComplete }
    set {
      var s = settings
      s.firstTaskWalkthroughComplete = newValue
      settings = s
    }
  }

  /// Whether onboarding is needed.
  ///
  /// Onboarding is required only until the user explicitly completes it.
  /// Other setup checks (repo/workspace/server readiness) are surfaced in the UI
  /// but should not trap users inside onboarding when sections are skipped.
  var needsOnboarding: Bool {
    // Check config FIRST - it's the authoritative source of truth.
    // This prevents onboarding from reappearing if state files are missing/corrupted.
    if let config = config, config.onboardingComplete {
      return false
    }
    
    // If config doesn't exist or doesn't say complete, check the onboarding state.
    // Load from workspace (parent of control repo), not control repo itself
    let workspacePath: String? = {
      guard let controlPath = config?.controlRepoPath, !controlPath.isEmpty else { return nil }
      return URL(fileURLWithPath: controlPath).deletingLastPathComponent().path
    }()
    let onboardingState = OnboardingStateManager.load(preferredWorkspacePath: workspacePath)
    
    // If onboarding is complete according to the state, auto-fix the config.
    if onboardingState.isCompleted(.done) {
      // Auto-fix: Create or update config to match the completion state.
      if let config = config {
        // Config exists but completion flag is wrong - fix it.
        var updatedConfig = config
        updatedConfig.onboardingComplete = true
        self.config = updatedConfig
        saveConfig()
      } else {
        // Config is missing entirely - create one with onboarding complete.
        // Use workspace path from onboarding state if available.
        let workspace = onboardingState.workspace ?? LobsPaths.defaultWorkspace
        let controlPath = (workspace as NSString).appendingPathComponent("lobs-control")
        let newConfig = AppConfig(
          controlRepoUrl: "",
          controlRepoPath: controlPath,
          onboardingComplete: true
        )
        self.config = newConfig
        saveConfig()
      }
      return false
    }
    
    return true
  }

  static func detectWorkspacePath(controlRepoPath: String) -> String {
    // Prefer explicit onboarding state (if present), otherwise fall back to
    // the parent directory of the configured control repo path.
    let s = OnboardingStateManager.load()
    if let ws = s.workspace?.trimmingCharacters(in: .whitespacesAndNewlines), !ws.isEmpty {
      return ws
    }

    let url = URL(fileURLWithPath: controlRepoPath)
    return url.deletingLastPathComponent().path
  }

  static func directoryExists(atPath path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
  }

  static func isOpenClawConfigured() -> Bool {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let openclawDir = home.appendingPathComponent(".openclaw")

    // OpenClaw's config format has changed over time; accept any of these.
    let candidates: [URL] = [
      openclawDir.appendingPathComponent("config.json"),
      openclawDir.appendingPathComponent("config.yaml"),
      openclawDir.appendingPathComponent("config.yml")
    ]

    return candidates.contains { fm.fileExists(atPath: $0.path) }
  }

  static func isGitRepo(atPath path: String) -> Bool {
    let repoPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !repoPath.isEmpty else { return false }

    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: repoPath, isDirectory: &isDir), isDir.boolValue else {
      return false
    }

    let gitDir = (repoPath as NSString).appendingPathComponent(".git")
    var isGitDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: gitDir, isDirectory: &isGitDir) && isGitDir.boolValue
  }

  @Published var tasks: [DashboardTask] = [] {
    didSet { invalidateFilteredTasksCache() }
  }
  @Published var selectedTaskId: String? = nil
  
  // Cached filtered tasks for performance
  private var _cachedFilteredTasks: [DashboardTask] = []
  private var _filteredTasksCacheValid: Bool = false

  // Research
  @Published var researchTiles: [ResearchTile] = []  // Legacy tiles
  @Published var researchRequests: [ResearchRequest] = []
  @Published var selectedTileId: String? = nil

  // Research Document (doc-based)
  @Published var researchDocContent: String = ""
  @Published var researchSources: [ResearchSource] = []
  @Published var researchDeliverables: [ResearchDeliverable] = []

  // Tracker
  @Published var trackerItems: [TrackerItem] = []
  @Published var trackerRequests: [ResearchRequest] = []

  // Inbox (Design Docs)
  @Published var inboxItems: [InboxItem] = []

  /// Read state for inbox documents.
  ///
  /// Note: we still mirror this into local settings for convenience/offline caching,
  /// but the source of truth is the control repo (see `state/inbox/read-state.json`).
  @Published var readItemIds: Set<String> = [] {
    didSet {
      guard !isApplyingInboxReadState else { return }
      var s = settings
      s.readInboxItemIds = Array(readItemIds)
      s.inboxReadStateUpdatedAt = Date()
      settings = s
      persistInboxReadStateDebounced()
    }
  }

  /// Tracks last-seen thread message count per doc ID. When a thread has more messages
  /// than this count, the item shows as having unread follow-ups.
  @Published var lastSeenThreadCounts: [String: Int] = [:] {
    didSet {
      guard !isApplyingInboxReadState else { return }
      var s = settings
      s.lastSeenThreadCounts = lastSeenThreadCounts
      s.inboxReadStateUpdatedAt = Date()
      settings = s
      persistInboxReadStateDebounced()
    }
  }
  @Published var showInbox: Bool = false
  @Published var inboxResponsesByDocId: [String: InboxResponse] = [:]
  @Published var inboxThreadsByDocId: [String: InboxThread] = [:]

  /// Threads with local edits that haven't been confirmed pushed yet.
  /// Prevents auto-refresh from overwriting freshly-posted messages.
  private var pendingThreadWrites: [String: InboxThread] = [:]

  // Agent Documents (Reports & Research)
  @Published var agentDocuments: [AgentDocument] = []
  @Published var readDocumentIds: Set<String> = [] {
    didSet {
      var s = settings
      s.readDocumentIds = Array(readDocumentIds)
      settings = s
    }
  }

  // Inbox read-state persistence (repo-backed)
  private var isApplyingInboxReadState: Bool = false
  private var inboxReadStateCommitTask: Task<Void, Never>? = nil

  // Project README
  @Published var projectReadme: String = ""

  // Worker Status
  @Published var workerStatus: WorkerStatus? = nil
  @Published var workerHistory: WorkerHistory? = nil

  // Agent Status
  @Published var agentStatuses: [String: AgentStatus] = [:]
  @Published var selectedAgentType: String? = nil

  // Main Session Usage
  @Published var mainSessionUsage: MainSessionUsage? = nil

  // Text Dumps
  @Published var textDumps: [TextDump] = []
  /// IDs of completed dumps the user has already reviewed.
  @Published var reviewedDumpIds: Set<String> = [] {
    didSet {
      var s = settings
      s.reviewedTextDumpIds = Array(reviewedDumpIds)
      settings = s
    }
  }
  /// Completed text dumps that haven't been reviewed yet.
  var unreviewedCompletedDumps: [TextDump] {
    textDumps.filter { $0.status == .completed && !reviewedDumpIds.contains($0.id) }
  }

  // Projects
  @Published var projects: [Project] = []
  /// Per-project last git commit time (computed from lobs-control repo history).
  @Published var projectLastCommitAt: [String: Date] = [:]

  // Overview (Home) cached stats
  struct ResearchOverviewStats: Equatable, Sendable {
    var openRequests: Int
    var totalRequests: Int
    var deliverables: Int
  }

  /// Cached per-project research stats used by OverviewView.
  ///
  /// Important: OverviewView must not hit the filesystem in computed properties.
  /// Doing so causes noticeable UI hitches during refreshes (SwiftUI recomputes body frequently).
  @Published var overviewResearchStatsByProject: [String: ResearchOverviewStats] = [:]

  /// Cached list of open research requests across all (active) research projects.
  /// Used for the Overview “Research” column and sheet.
  @Published var overviewOpenResearchRequests: [ResearchRequest] = []

  private var overviewResearchRefreshTask: Task<Void, Never>? = nil

  @Published var selectedProjectId: String = "default" {
    didSet {
      var s = settings
      s.selectedProjectId = selectedProjectId
      settings = s
      loadResearchData()
      loadTrackerData()
      loadProjectReadme()
      invalidateFilteredTasksCache()
    }
  }

  /// When true, the overview/home screen is shown instead of a project board.
  @Published var showOverview: Bool = true
  @Published var artifactText: String = "(select a task)"
  @Published var lastError: String? = nil

  /// Transient error banner — shown briefly then auto-dismissed.
  @Published var errorBanner: String? = nil
  /// Transient success banner — shown briefly then auto-dismissed.
  @Published var successBanner: String? = nil

  /// Whether a background git operation is in flight.
  @Published var isGitBusy: Bool = false

  /// Whether sync is blocked because the local repo couldn't be rebased cleanly onto origin.
  @Published var syncBlockedByUncommitted: Bool = false

  // Sync conflict recovery UI
  @Published var syncConflictDetailsPresented: Bool = false
  @Published var syncConflictFiles: [String] = []
  @Published var syncConflictLastError: String? = nil

  // Rebase recovery UI (stuck rebase on crash/force quit)
  @Published var rebaseRecoveryPresented: Bool = false
  @Published var rebaseRecoveryConflictFiles: [String] = []
  @Published var rebaseRecoveryLastError: String? = nil

  /// Number of pending local changes not yet pushed.
  @Published var pendingChangesCount: Int = 0

  // Git push visibility
  /// Timestamp of the last successful push to origin (best-effort; set when dashboard pushes).
  @Published var lastSuccessfulPushAt: Date? = nil
  /// Timestamp of the last push attempt (best-effort).
  @Published var lastPushAttemptAt: Date? = nil
  /// Last push error message (if any). When set, UI should treat remote-derived state as potentially stale.
  @Published var lastPushError: String? = nil

  // Manual force-sync UI state
  /// When true, the UI should prompt the user to confirm escalating from --force-with-lease to --force.
  @Published var forcePushEscalationPresented: Bool = false
  /// Error that triggered the escalation prompt (best-effort).
  @Published var forcePushEscalationError: String? = nil

  // Notifications
  @Published var notifications: [DashboardNotification] = []
  @Published var notificationPreferences: NotificationPreferences = .default
  private var batchedNotifications: [DashboardNotification] = []
  private var batchTimer: Timer? = nil
  /// Commit hash of last successful push.
  @Published var lastPushedCommitHash: String? = nil

  /// Debounced auto-push queue: not needed in API mode (server handles persistence)
  // private lazy var gitAutoPushQueue = GitAutoPushQueue(owner: self, debounceSeconds: 10.0)

  // Control repo sync status
  /// How many commits local HEAD is ahead of origin/main (unpublished changes).
  @Published var controlRepoAhead: Int = 0
  /// How many commits origin/main is ahead of local HEAD (need to pull).
  @Published var controlRepoBehind: Int = 0
  /// Last time control repo status was checked (for throttling)
  private var lastControlRepoStatusCheck: Date? = nil
  /// Last time pending changes count was updated (for throttling)
  private var lastPendingChangesUpdate: Date? = nil

  // GitHub sync status (for collaborative projects)
  /// Timestamp of the last successful GitHub sync.
  @Published var lastGitHubSyncAt: Date? = nil
  /// Last GitHub sync error message (if any).
  @Published var lastGitHubSyncError: String? = nil
  /// True when actively syncing with GitHub.
  @Published var isGitHubSyncing: Bool = false

  // Dashboard update indicator
  /// True when origin/main of the lobs-dashboard repo is ahead of the local HEAD.
  @Published var dashboardUpdateAvailable: Bool = false
  /// Short hash of the local HEAD in lobs-dashboard repo.
  @Published var dashboardLocalCommit: String = ""
  /// Short hash of origin/main HEAD in lobs-dashboard repo.
  @Published var dashboardRemoteCommit: String = ""
  /// How many commits origin/main is ahead of the local built commit.
  @Published var dashboardCommitsBehind: Int = 0
  /// True when local HEAD is ahead of the built commit (pulled but not compiled).
  @Published var dashboardNeedsRebuild: Bool = false
  /// One-line summaries of pending update commits (for display in popover).
  @Published var dashboardUpdateCommits: [String] = []

  // Self-update state
  /// Whether a self-update (pull + build + relaunch) is in progress.
  @Published var isUpdating: Bool = false
  /// Progress log lines from the update process.
  @Published var updateLog: [String] = []
  /// Error message if the update failed.
  @Published var updateError: String? = nil

  // Kanban UX
  @Published var searchText: String = "" {
    didSet { invalidateFilteredTasksCache() }
  }
  @Published var multiSelectedTaskIds: Set<String> = []

  /// Whether multi-select mode is currently active.
  var isMultiSelectActive: Bool { !multiSelectedTaskIds.isEmpty }

  /// Toggle a task in/out of the multi-selection.
  func toggleMultiSelect(taskId: String) {
    if multiSelectedTaskIds.contains(taskId) {
      multiSelectedTaskIds.remove(taskId)
    } else {
      multiSelectedTaskIds.insert(taskId)
    }
  }

  /// Clear multi-selection.
  func clearMultiSelect() {
    multiSelectedTaskIds.removeAll()
  }

  /// Inbox is treated as a filter, not a column.
  @Published var showInboxOnly: Bool = false {
    didSet { invalidateFilteredTasksCache() }
  }
  @Published var ownerFilter: String = "all" {
    didSet {
      var s = settings
      s.ownerFilter = ownerFilter
      settings = s
      invalidateFilteredTasksCache()
    }
  }

  /// Filter tasks by shape/type. nil = show all.
  @Published var shapeFilter: TaskShape? = nil {
    didSet { invalidateFilteredTasksCache() }
  }
  @Published var wipLimitActive: Int = 6 {
    didSet {
      var s = settings
      s.wipLimitActive = wipLimitActive
      settings = s
    }
  }

  // Completed hygiene
  @Published var completedShowRecent: Int = 30 {
    didSet {
      var s = settings
      s.completedShowRecent = completedShowRecent
      settings = s
    }
  }
  @Published var autoArchiveCompleted: Bool = true {
    didSet {
      var s = settings
      s.autoArchiveCompleted = autoArchiveCompleted
      settings = s
    }
  }
  @Published var archiveCompletedAfterDays: Int = 7 {
    didSet {
      var s = settings
      s.archiveCompletedAfterDays = archiveCompletedAfterDays
      settings = s
    }
  }

  // Inbox hygiene
  @Published var autoArchiveReadInbox: Bool = true {
    didSet {
      var s = settings
      s.autoArchiveReadInbox = autoArchiveReadInbox
      settings = s
    }
  }
  @Published var archiveReadInboxAfterDays: Int = 7 {
    didSet {
      var s = settings
      s.archiveReadInboxAfterDays = archiveReadInboxAfterDays
      settings = s
    }
  }

  // Popover state for task detail
  @Published var popoverTaskId: String? = nil

  // Appearance
  /// 0 = System, 1 = Light, 2 = Dark
  @Published var appearanceMode: Int = 0 {
    didSet {
      var s = settings
      s.appearanceMode = appearanceMode
      settings = s
      applyAppearance()
    }
  }

  // Quick Capture
  /// 0 = ⌘⇧Space, 1 = ⌥Space
  @Published var quickCaptureHotkeyMode: Int = 1 {
    didSet {
      var s = settings
      s.quickCaptureHotkeyMode = quickCaptureHotkeyMode
      settings = s
    }
  }

  // Auto-refresh
  @Published var autoRefreshEnabled: Bool = true {
    didSet {
      var s = settings
      s.autoRefreshEnabled = autoRefreshEnabled
      settings = s
    }
  }
  @Published var autoRefreshIntervalSeconds: Int = 30 {
    didSet {
      var s = settings
      s.autoRefreshIntervalSeconds = autoRefreshIntervalSeconds
      settings = s
    }
  }
  private var refreshTimer: Timer?

  init() {
    // Load config from ConfigManager (includes automatic migration from UserDefaults)
    let loadedConfig = ConfigManager.load()

    // Initialize API service
    let baseURL = loadedConfig?.serverURL ?? "http://localhost:8000"
    api = (try? APIService(baseURLString: baseURL)) ?? APIService(baseURL: URL(string: "http://localhost:8000")!)
    config = loadedConfig
    
    // Load repo path from config
    if let loadedConfig {
      repoPath = loadedConfig.controlRepoPath
      
      // Load all settings from config
      let s = loadedConfig.settings
      selectedProjectId = s.selectedProjectId
      ownerFilter = s.ownerFilter
      wipLimitActive = s.wipLimitActive
      completedShowRecent = s.completedShowRecent
      autoArchiveCompleted = s.autoArchiveCompleted
      archiveCompletedAfterDays = s.archiveCompletedAfterDays
      autoArchiveReadInbox = s.autoArchiveReadInbox
      archiveReadInboxAfterDays = s.archiveReadInboxAfterDays
      autoRefreshEnabled = s.autoRefreshEnabled
      autoRefreshIntervalSeconds = s.autoRefreshIntervalSeconds
      readItemIds = Set(s.readInboxItemIds)
      lastSeenThreadCounts = s.lastSeenThreadCounts
      readDocumentIds = Set(s.readDocumentIds)
      reviewedDumpIds = Set(s.reviewedTextDumpIds)
      appearanceMode = s.appearanceMode
      quickCaptureHotkeyMode = s.quickCaptureHotkeyMode
    } else {
      // No config yet (fresh install or migration failed)
      repoPath = ""
      // Properties will use their default values from UserSettings()
    }

    // Auto-detect a default lobs-control checkout on fresh installs.
    // If ~/lobs-control exists and is a git repo, adopt it so the app can launch
    // without forcing onboarding.
    let defaultRepoPath = (NSHomeDirectory() as NSString).appendingPathComponent("lobs-control")
    if repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      if Self.isGitRepo(atPath: defaultRepoPath) {
        _ = setControlRepo(path: defaultRepoPath, repoUrl: config?.controlRepoUrl, onboardingComplete: true)
      }
    } else {
      // If config points at a path that no longer exists, clear the in-memory repoPath
      // so downstream code doesn't try to read from it.
      if !Self.isGitRepo(atPath: repoPath) {
        repoPath = ""
      }
    }
    
    applyAppearance()
    startAutoRefreshIfNeeded()

    // Load documents immediately on launch (don't wait for first refresh)
    if let repoURL {
      loadAgentDocuments()
    }

    // Check for dashboard source updates on launch
    checkForDashboardUpdate()

    // Setup app activity monitoring for automatic pause/resume of refresh
    setupActivityMonitoring()
    
    // Clear legacy UserDefaults after successful migration (one-time cleanup)
    // Only do this if we successfully loaded a config
    if config != nil {
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
        ConfigManager.clearLegacyUserDefaults()
      }
    }
  }

  private var wasAutoRefreshEnabledBeforePause: Bool = true

  private func setupActivityMonitoring() {
    // Pause refresh when app becomes inactive (user switches away)
    NotificationCenter.default.addObserver(
      forName: NSApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      // Only pause if auto-refresh is currently enabled
      if self.autoRefreshEnabled {
        self.wasAutoRefreshEnabledBeforePause = true
        self.refreshTimer?.invalidate()
        self.refreshTimer = nil
      }
    }

    // Resume refresh when app becomes active again
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      // Only resume if we paused it (user had auto-refresh enabled)
      if self.wasAutoRefreshEnabledBeforePause && self.autoRefreshEnabled {
        self.startAutoRefreshIfNeeded()
        // Do an immediate refresh when becoming active
        Task { @MainActor in
          await self.silentReload()
        }
      }
    }
  }

  var selectedProject: Project? {
    projects.first(where: { $0.id == selectedProjectId })
  }

  /// Active (non-archived) projects sorted by sortOrder then createdAt.
  var sortedActiveProjects: [Project] {
    projects.filter { ($0.archived ?? false) == false }
      .sorted { a, b in
        let oa = a.sortOrder ?? Int.max
        let ob = b.sortOrder ?? Int.max
        if oa != ob { return oa < ob }
        return a.createdAt < b.createdAt
      }
  }

  var isResearchProject: Bool {
    selectedProject?.resolvedType == .research
  }

  var isTrackerProject: Bool {
    selectedProject?.resolvedType == .tracker
  }

  func startAutoRefreshIfNeeded() {
    refreshTimer?.invalidate()
    refreshTimer = nil
    guard autoRefreshEnabled else { return }
    refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoRefreshIntervalSeconds), repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.silentReload()
      }
    }
  }

  func applyAppearance() {
    switch appearanceMode {
    case 1:
      NSApp.appearance = NSAppearance(named: .aqua)
    case 2:
      NSApp.appearance = NSAppearance(named: .darkAqua)
    default:
      NSApp.appearance = nil  // follow system
    }
  }

  private func sortTasksForUX(_ tasks: inout [DashboardTask]) {
    // Stable ordering for UX.
    // Pinned tasks float to top, then respect manual sortOrder, then creation time.
    tasks.sort { (a, b) in
      if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
      let ap = a.pinned ?? false
      let bp = b.pinned ?? false
      if ap != bp { return ap }
      let oa = a.sortOrder ?? Int.max
      let ob = b.sortOrder ?? Int.max
      if oa != ob { return oa < ob }
      if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
      return a.updatedAt > b.updatedAt
    }
  }

  /// Reload without clearing error state if nothing changed.
  func silentReload() {
    guard let repoURL else { return }
    // Skip if already syncing to avoid stacking requests
    guard !isGitBusy else { return }
    isGitBusy = true
    Task {
      do {
        // Run git sync off the main thread to avoid UI lag
        try await syncRepoAsync(repoURL: repoURL)
      } catch {
        await MainActor.run { isGitBusy = false }
        return
      }

      // Capture main-actor properties before detaching
      let shouldAutoArchiveCompleted = autoArchiveCompleted
      let archiveAfterDays = archiveCompletedAfterDays
      let shouldAutoArchiveReadInbox = autoArchiveReadInbox
      let archiveReadAfterDays = archiveReadInboxAfterDays
      let currentReadItemIds = await readItemIds

      // Load data off the main thread to avoid blocking UI
      let loadedData: (projects: [Project], tasks: [DashboardTask], hasGitHubProject: Bool)? = await Task.detached { [weak self] in
        guard let self = self else { return nil }
        do {
          // Projects
          let pfile = try await self.api.loadProjects()
          var loadedProjects = pfile.projects

          // Auto-archive is handled server-side, no need to do it client-side

          // Track GitHub sync status if selected project uses GitHub mode
          let hasGitHubProject = loadedProjects.contains { $0.tracking == .github && $0.github != nil }

          let file = try await self.api.loadTasks()

          return (loadedProjects, file.tasks, hasGitHubProject)
        } catch {
          print("⚠️ [reload:silent] Failed loading projects/tasks from API: \(AppViewModel.describeLoadError(error))")
          return nil
        }
      }.value

      // Back on main actor — update UI with loaded data
      await MainActor.run {
        guard let data = loadedData else {
          let hasGitHubProject = projects.contains { $0.syncMode == .github && $0.githubConfig != nil }
          if hasGitHubProject {
            lastGitHubSyncError = "Failed to load data"
            isGitHubSyncing = false
          }
          print("⚠️ [reload:silent] Keeping previous in-memory state due to disk load failure")
          isGitBusy = false
          return
        }

        // Update projects
        if data.projects.map({ $0.id }) != projects.map({ $0.id }) {
          projects = data.projects
        }
        if !projects.contains(where: { $0.id == selectedProjectId }) {
          selectedProjectId = "default"
        }

        // Update GitHub sync status
        if data.hasGitHubProject {
          lastGitHubSyncAt = Date()
          lastGitHubSyncError = nil
          isGitHubSyncing = false
        }

        // Only update if something changed (avoid UI flicker).
        if data.tasks.map({ $0.id }).sorted() != tasks.map({ $0.id }).sorted()
          || data.tasks.map({ $0.updatedAt }) != tasks.map({ $0.updatedAt })
          || data.tasks.map({ $0.status.rawValue }) != tasks.map({ $0.status.rawValue }) {
          tasks = data.tasks
          loadArtifactForSelected()
        }

        // Refresh cached Overview stats (runs in background)
        self.refreshOverviewResearchStats()

        isGitBusy = false
      }

      // Load secondary data in background (non-blocking)
      Task.detached(priority: .utility) { [weak self] in
        guard let self = self else { return }
        
        // These can happen async without blocking the main UI
        await self.loadResearchDataAsync()
        await self.loadTrackerDataAsync()
        await self.loadInboxItemsAsync()
        await self.loadWorkerStatusAsync()
        await self.loadAgentStatusesAsync()
        await self.loadAgentDocumentsAsync()
      }

      // Check for updates in background (low priority)
      Task.detached(priority: .utility) {
        await self.checkForDashboardUpdateAsync()
        await self.checkControlRepoStatusAsync()
        await self.updatePendingChangesCountAsync()
      }
    }
  }

  // MARK: - Overview Research Stats (cached)

  /// Refresh cached research stats for the Overview screen.
  /// Runs off the main thread and publishes results back on the MainActor.
  func refreshOverviewResearchStats() {
    let projectsSnapshot = projects.filter { ($0.archived ?? false) == false }

    // Cancel any in-flight refresh to avoid piling up work during rapid refreshes.
    overviewResearchRefreshTask?.cancel()
    overviewResearchRefreshTask = Task.detached(priority: .utility) { [weak self, projectsSnapshot] in
      guard let self = self else { return }

      var stats: [String: ResearchOverviewStats] = [:]
      var openRequests: [ResearchRequest] = []

      for p in projectsSnapshot where p.resolvedType == .research {
        if Task.isCancelled { return }

        do {
          let requests = try await api.loadResearchRequests(projectId: p.id)
          let openCount = requests.filter { $0.status == .open }.count
          
          stats[p.id] = ResearchOverviewStats(
            openRequests: openCount,
            totalRequests: requests.count,
            deliverables: 0
          )
          
          openRequests += requests.filter { $0.status == .open }
        } catch {
          print("⚠️ Failed to load research requests for \(p.id): \(error)")
          stats[p.id] = ResearchOverviewStats(
            openRequests: 0,
            totalRequests: 0,
            deliverables: 0
          )
        }
      }

      await MainActor.run {
        // If a new refresh started while we were working, don't publish stale results.
        guard !Task.isCancelled else { return }
        self.overviewResearchStatsByProject = stats
        self.overviewOpenResearchRequests = openRequests
      }
    }
  }

  var repoURL: URL? {
    guard !repoPath.isEmpty else { return nil }
    return URL(fileURLWithPath: repoPath)
  }

  /// Set the control repo path (and optionally URL) and persist config.
  ///
  /// - Parameters:
  ///   - path: Local filesystem path to the lobs-control repository.
  ///   - repoUrl: Optional git URL for the control repository.
  ///   - onboardingComplete: If non-nil, updates the onboarding completion flag.
  @discardableResult
  func setControlRepo(path: String, repoUrl: String? = nil, onboardingComplete: Bool? = nil) -> Bool {
    repoPath = path

    var updatedConfig = config ?? AppConfig()
    updatedConfig.controlRepoPath = path
    if let repoUrl {
      updatedConfig.controlRepoUrl = repoUrl
    }
    if let onboardingComplete {
      updatedConfig.onboardingComplete = onboardingComplete
    }
    config = updatedConfig

    do {
      try ConfigManager.save(updatedConfig)
      return true
    } catch {
      let msg = "Failed to save config: \(error)"
      print("⚠️ \(msg)")
      lastError = msg
      return false
    }
  }

  func setRepoURL(_ url: URL) {
    // Legacy API used by the repo picker; selecting a repo implies onboarding is complete.
    setControlRepo(path: url.path, repoUrl: nil, onboardingComplete: true)
  }

  /// URL of the lobs-dashboard repo — derived as sibling of lobs-control.
  var dashboardRepoURL: URL? {
    guard let controlURL = repoURL else { return nil }
    let parent = controlURL.deletingLastPathComponent()
    let dashURL = parent.appendingPathComponent("lobs-dashboard")
    // Verify it's a git repo
    let gitDir = dashURL.appendingPathComponent(".git")
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir), isDir.boolValue {
      return dashURL
    }
    return nil
  }

  /// The commit hash that this binary was built from.
  /// Reads from ~/Library/Application Support/Lobs/dashboard-build-commit (written by bin/build at build time),
  /// falling back to the compile-time BuildInfo.builtCommit.
  private var builtFromCommit: String {
    // Prefer the runtime hash file written by bin/build — this survives pulls
    // without recompilation and always reflects the actual last build.
    let hashFile = LobsPaths.buildCommit
    if let diskHash = try? String(contentsOf: hashFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines),
       !diskHash.isEmpty {
      return diskHash
    }
    // Fallback to compile-time constant
    let hash = BuildInfo.builtCommit
    return hash.isEmpty || hash == "unknown" ? "" : hash
  }

  /// Last time we checked for lobs-dashboard updates.
  /// Throttled to avoid frequent background fetches that can burn energy.
  private var lastDashboardUpdateCheckAt: Date? = nil

  /// Check if lobs-dashboard has new commits on origin/main that haven't been built.
  func checkForDashboardUpdate(force: Bool = false) {
    guard let dashURL = dashboardRepoURL else { return }

    // Throttle update checks (git fetch) — this can be surprisingly expensive.
    // Manual refreshes can bypass throttling.
    if !force {
      let minInterval: TimeInterval = 60 * 5 // 5 minutes
      if let last = lastDashboardUpdateCheckAt,
         Date().timeIntervalSince(last) < minInterval {
        return
      }
    }
    lastDashboardUpdateCheckAt = Date()

    Task {
      do {
        // Fetch latest from remote
        let fetch = try await Git.runAsync(["fetch", "origin"], cwd: dashURL)
        guard fetch.ok else { return }

        // Get local HEAD hash (full)
        let localFullResult = try await Git.runAsync(["rev-parse", "HEAD"], cwd: dashURL)
        guard localFullResult.ok else { return }
        let _ = localFullResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get local HEAD hash (short, for display)
        let localResult = try await Git.runAsync(["rev-parse", "--short", "HEAD"], cwd: dashURL)
        guard localResult.ok else { return }
        let localHash = localResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get origin/main hash
        let remoteResult = try await Git.runAsync(["rev-parse", "--short", "origin/main"], cwd: dashURL)
        guard remoteResult.ok else { return }
        let remoteHash = remoteResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Count commits behind origin/main
        let behindResult = try await Git.runAsync(
          ["rev-list", "--count", "HEAD..origin/main"], cwd: dashURL
        )
        let behindRemote = Int(behindResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Check if local HEAD is ahead of the build commit (pulled but not compiled)
        var needsRebuild = false
        var aheadOfBuild = 0
        let built = builtFromCommit
        if !built.isEmpty {
          // Count commits between build commit and HEAD
          let aheadResult = try await Git.runAsync(
            ["rev-list", "--count", "\(built)..HEAD"], cwd: dashURL
          )
          aheadOfBuild = Int(aheadResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
          needsRebuild = aheadOfBuild > 0
        }

        // Total commits that need attention = behind remote + ahead of build (pulled but uncompiled)
        let totalBehind = behindRemote + aheadOfBuild

        // Fetch one-line commit summaries for the pending updates
        var commits: [String] = []
        if needsRebuild && !built.isEmpty {
          let logResult = try await Git.runAsync(
            ["log", "--oneline", "\(built)..HEAD"], cwd: dashURL
          )
          if logResult.ok {
            commits += logResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
              .split(separator: "\n").map(String.init)
          }
        }
        if behindRemote > 0 {
          let logResult = try await Git.runAsync(
            ["log", "--oneline", "HEAD..origin/main"], cwd: dashURL
          )
          if logResult.ok {
            commits += logResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
              .split(separator: "\n").map(String.init)
          }
        }

        self.dashboardLocalCommit = localHash
        self.dashboardRemoteCommit = remoteHash
        self.dashboardCommitsBehind = totalBehind
        self.dashboardUpdateAvailable = totalBehind > 0
        self.dashboardNeedsRebuild = needsRebuild && behindRemote == 0
        self.dashboardUpdateCommits = commits
      } catch {
        print("[update-check] failed: \(error)")
      }
    }
  }

  /// Check how many commits local HEAD is ahead/behind origin/main for the control repo.
  func checkControlRepoStatus() {
    guard let repoURL else { return }

    Task {
      do {
        // Get ahead count (local commits not pushed)
        let aheadRes = try await Git.runAsync(["rev-list", "--count", "origin/main..HEAD"], cwd: repoURL)
        let aheadCount = Int(aheadRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Get behind count (remote commits not pulled)
        let behindRes = try await Git.runAsync(["rev-list", "--count", "HEAD..origin/main"], cwd: repoURL)
        let behindCount = Int(behindRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        await MainActor.run {
          self.controlRepoAhead = aheadCount
          self.controlRepoBehind = behindCount
        }
      } catch {
        print("[control-repo-status] failed: \(error)")
      }
    }
  }

  /// Perform a self-update: git pull --rebase, ./bin/build, then relaunch the app.
  func performSelfUpdate() {
    guard let dashURL = dashboardRepoURL else {
      updateError = "Cannot find lobs-dashboard repo"
      return
    }
    guard !isUpdating else { return }

    isUpdating = true
    updateLog = []
    updateError = nil

    Task {
      do {
        // Step 1: git pull --rebase
        updateLog.append("Pulling latest changes…")
        let pull = try await Git.runAsync(["pull", "--rebase"], cwd: dashURL)
        if !pull.ok {
          updateError = "git pull failed: \(pull.stderr)"
          isUpdating = false
          return
        }
        let pullMsg = pull.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pullMsg.isEmpty {
          updateLog.append(pullMsg)
        }

        // Step 2: Run ./bin/build
        updateLog.append("Building…")
        let buildResult = try await runBuildScript(cwd: dashURL)
        if !buildResult.ok {
          updateError = "Build failed: \(buildResult.stderr)"
          isUpdating = false
          return
        }
        updateLog.append("Build succeeded!")

        // Step 3: Relaunch
        updateLog.append("Relaunching…")
        // Small delay so the user can see the success message
        try await Task.sleep(nanoseconds: 500_000_000)
        relaunchApp(dashURL: dashURL)
      } catch {
        updateError = "Update failed: \(error.localizedDescription)"
        isUpdating = false
      }
    }
  }

  /// Run the bin/build script asynchronously and return the result.
  private func runBuildScript(cwd: URL) async throws -> Git.Result {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let proc = Process()
          proc.executableURL = URL(fileURLWithPath: "/bin/bash")
          proc.arguments = [cwd.appendingPathComponent("bin/build").path]
          proc.currentDirectoryURL = cwd

          // The build script temporarily overrides HOME for SwiftPM caching.
          // Pass through the current environment.
          proc.environment = ProcessInfo.processInfo.environment

          let out = Pipe()
          let err = Pipe()
          proc.standardOutput = out
          proc.standardError = err

          try proc.run()
          proc.waitUntilExit()

          let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
          let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

          continuation.resume(returning: Git.Result(
            exitCode: proc.terminationStatus,
            stdout: stdout,
            stderr: stderr
          ))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Relaunch the app by launching the newly built binary from `swift build`.
  ///
  /// We intentionally spawn a new process and then terminate the current app.
  /// Using `nohup` + redirected stdio makes the relaunch resilient even if the
  /// parent process exits quickly.
  private func relaunchApp(dashURL: URL) {
    // Prefer launching the newly built SwiftPM binary.
    let binaryPath = dashURL.appendingPathComponent(".build/debug/LobsDashboard").path
    let fm = FileManager.default

    // Fallbacks:
    // - If running from an .app bundle, relaunch the bundle
    // - Otherwise, run `swift run --skip-build` from the repo
    let appBundlePath: String? = {
      let bundleURL = Bundle.main.bundleURL
      return bundleURL.pathExtension == "app" ? bundleURL.path : nil
    }()

    let script: String
    if fm.isExecutableFile(atPath: binaryPath) {
      script = "(sleep 0.5; nohup \"\(binaryPath)\" >/dev/null 2>&1 &) </dev/null >/dev/null 2>&1"
    } else if let appBundlePath {
      script = "(sleep 0.5; nohup /usr/bin/open -n \"\(appBundlePath)\" >/dev/null 2>&1 &) </dev/null >/dev/null 2>&1"
    } else {
      // Last resort: re-run via SwiftPM.
      script = "(cd \"\(dashURL.path)\" && sleep 0.5; nohup swift run --skip-build LobsDashboard >/dev/null 2>&1 &) </dev/null >/dev/null 2>&1"
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    proc.environment = ProcessInfo.processInfo.environment
    proc.standardInput = FileHandle.nullDevice
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice

    do {
      try proc.run()
    } catch {
      // If we fail to relaunch, keep the app running and show an error.
      updateError = "Relaunch failed: \(error.localizedDescription)"
      isUpdating = false
      return
    }

    DispatchQueue.main.async {
      NSApplication.shared.terminate(nil)
    }
  }

  func reloadIfPossible() {
    guard repoURL != nil else { return }
    reload()
  }

  func reload() {
    guard let repoURL else {
      lastError = "Repo path not set"
      return
    }

    // If a previous sync crashed mid-rebase, prompt for recovery before doing anything else.
    promptRebaseRecoveryIfNeeded(context: "startup/reload")
    if rebaseRecoveryPresented {
      isGitBusy = false
      return
    }

    isGitBusy = true
    Task {
      // Try to sync, but don't fail if it errors - we can still load local data
      do {
        // Run git sync off the main thread to avoid UI lag
        try await syncRepoAsync(repoURL: repoURL)
      } catch {
        await MainActor.run {
          lastError = String(describing: error)
        }
        // Continue to load data even if sync failed
      }

      // Capture main-actor properties before detaching
      let shouldAutoArchiveCompleted = autoArchiveCompleted
      let archiveAfterDays = archiveCompletedAfterDays
      let shouldAutoArchiveReadInbox = autoArchiveReadInbox
      let archiveReadAfterDays = archiveReadInboxAfterDays
      let currentReadItemIds = await readItemIds
      let currentProjectId = selectedProjectId

      // Load data off the main thread to avoid blocking UI
      let loadedData: (projects: [Project], tasks: [DashboardTask], hasGitHubProject: Bool, githubSyncTime: Date?)? = await Task.detached { [weak self] in
        guard let self = self else { return nil }
        do {
          // Projects
          let pfile = try await self.api.loadProjects()
          var loadedProjects = pfile.projects

          // Auto-archive is handled server-side

          // Track GitHub sync status if any project uses GitHub mode
          let hasGitHubProject = loadedProjects.contains { $0.tracking == .github && $0.github != nil }

          let file = try await self.api.loadTasks()

          // Get GitHub sync timestamp
          // TODO: API endpoint needed for GitHub cache timestamp
          let githubSyncTime: Date? = nil

          return (loadedProjects, file.tasks, hasGitHubProject, githubSyncTime)
        } catch {
          print("⚠️ [reload] Failed loading projects/tasks from API: \(AppViewModel.describeLoadError(error))")
          return nil
        }
      }.value

      // Back on main actor — update UI with loaded data
      await MainActor.run {
        guard let data = loadedData else {
          let hasGitHubProject = projects.contains { $0.tracking == .github && $0.github != nil }
          if hasGitHubProject {
            lastGitHubSyncError = "Failed to load data"
            isGitHubSyncing = false
          }
          lastError = "Failed to load data"
          print("⚠️ [reload] Keeping previous in-memory state due to disk load failure")
          isGitBusy = false
          return
        }

        // Update projects
        projects = data.projects
        if !projects.contains(where: { $0.id == selectedProjectId }) {
          selectedProjectId = "default"
        }

        // Update GitHub sync status
        if data.hasGitHubProject {
          lastGitHubSyncAt = data.githubSyncTime
          lastGitHubSyncError = nil
          isGitHubSyncing = false
        }

        // Update tasks
        tasks = data.tasks
        lastError = nil
        
        loadArtifactForSelected()

        // Refresh cached Overview stats (runs in background)
        self.refreshOverviewResearchStats()

        isGitBusy = false
      }

      // Load secondary data in background (non-blocking)
      Task.detached(priority: .utility) { [weak self] in
        guard let self = self else { return }
        
        await self.loadResearchDataAsync()
        await self.loadTrackerDataAsync()
        await self.loadInboxItemsAsync()
        await self.loadWorkerStatusAsync()
        
        await MainActor.run {
          self.loadProjectReadme()
          self.loadTemplates()
          self.loadTextDumps()
        }
      }

      // Check for updates in background (low priority)
      Task.detached(priority: .utility) {
        await self.checkForDashboardUpdateAsync()
        await self.checkControlRepoStatusAsync(force: true)
        await self.updatePendingChangesCountAsync(force: true)
      }
    }
  }

  /// Sync GitHub cache via API for the current project.
  func syncGitHubCache() {
    guard let currentProject = projects.first(where: { $0.id == selectedProjectId }),
          currentProject.tracking == .github else {
      flashError("Current project is not GitHub-tracked")
      return
    }
    guard !isGitHubSyncing && !isGitBusy else { return }

    isGitHubSyncing = true
    Task {
      do {
        try await api.syncGitHubProject(projectId: currentProject.id)
        await MainActor.run {
          isGitHubSyncing = false
          reload()
        }
      } catch {
        await MainActor.run {
          flashError("Failed to sync GitHub: \(error.localizedDescription)")
          isGitHubSyncing = false
        }
      }
    }
  }

  /// Manually push local commits to origin.
  /// Useful when Auto-push is disabled or when a previous push failed.
  func pushNow() {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    Task {
      await MainActor.run {
        self.lastPushAttemptAt = Date()
      }
      
      // Check for uncommitted changes
      let status = await Git.runAsyncWithErrorHandling(["status", "--porcelain"], cwd: repoURL)
      if !status.success {
        await MainActor.run {
          self.lastPushError = status.error?.errorDescription ?? "Failed to check status"
          self.flashError(self.lastPushError ?? "Push failed")
          self.isGitBusy = false
        }
        return
      }
      
      let hasLocalChanges = !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      if hasLocalChanges {
        do {
          try await autoCommitLocalChangesAsync(repoURL: repoURL)
        } catch {
          await MainActor.run {
            self.lastPushError = "Failed to commit local changes"
            self.flashError(self.lastPushError ?? "Push failed")
            self.isGitBusy = false
          }
          return
        }
      }

      // Attempt push; retry transient failures before surfacing UI error.
      let pushAttempt = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
      if !pushAttempt.success {
        if pushAttempt.suggestsPull {
          let pull = await Git.runWithRetry(["pull", "--rebase"], cwd: repoURL, maxRetries: 2)
          if !pull.success {
            await MainActor.run {
              let errorMsg = pull.error?.errorDescription ?? "Pull failed"
              self.lastPushError = "Push failed: \(errorMsg)"
              self.flashError(self.lastPushError ?? "Push failed")
              self.isGitBusy = false
            }
            return
          }

          let retryPush = await Git.runWithRetry(["push"], cwd: repoURL, maxRetries: 3, initialDelay: 2.0)
          if !retryPush.success {
            await MainActor.run {
              let errorMsg = retryPush.error?.errorDescription ?? "Push failed"
              self.lastPushError = errorMsg
              self.flashError(self.lastPushError ?? "Push failed")
              self.isGitBusy = false
            }
            return
          }
        } else if pushAttempt.canRetry {
          let retryPush = await Git.runWithRetry(["push"], cwd: repoURL, maxRetries: 3, initialDelay: 2.0)
          if !retryPush.success {
            await MainActor.run {
              let errorMsg = retryPush.error?.errorDescription ?? "Push failed"
              self.lastPushError = errorMsg
              self.flashError(self.lastPushError ?? "Push failed")
              self.isGitBusy = false
            }
            return
          }
        } else {
          await MainActor.run {
            let errorMsg = pushAttempt.error?.errorDescription ?? "Push failed"
            self.lastPushError = errorMsg
            self.flashError(self.lastPushError ?? "Push failed")
            self.isGitBusy = false
          }
          return
        }
      }

      // Get current commit hash for display
      let hashResult = await Git.runAsyncWithErrorHandling(["rev-parse", "--short", "HEAD"], cwd: repoURL)
      let commitHash = hashResult.success ? hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil

      await MainActor.run {
        self.lastSuccessfulPushAt = Date()
        self.lastPushedCommitHash = commitHash
        self.lastPushError = nil
        self.flashSuccess("Pushed to origin")
        self.isGitBusy = false
      }
    }
  }

  // MARK: - Sync Conflict Recovery

  /// Option 1: Keep My Changes
  /// - Abort any in-progress rebase
  /// - Stash local changes
  /// - Reset hard to origin/main
  /// - Pop stash
  /// - Commit + push
  func recoverSyncConflictKeepMine() {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    syncConflictLastError = nil

    Task {
      // Best-effort abort (may fail if no rebase in progress)
      _ = await Git.runAsyncWithErrorHandling(["rebase", "--abort"], cwd: repoURL)

      let stash = await Git.runAsyncWithErrorHandling(["stash"], cwd: repoURL)
      if !stash.success {
        await MainActor.run {
          self.syncConflictLastError = stash.error?.errorDescription ?? "Failed to stash changes"
          self.flashError(self.syncConflictLastError ?? "Sync recovery failed")
          self.isGitBusy = false
        }
        return
      }

      let fetch = await Git.runAsyncWithErrorHandling(["fetch", "origin"], cwd: repoURL)
      if !fetch.success {
        await MainActor.run {
          self.syncConflictLastError = fetch.error?.errorDescription ?? "Fetch failed"
          self.flashError(self.syncConflictLastError ?? "Sync recovery failed")
          self.isGitBusy = false
        }
        return
      }

      let reset = await Git.runAsyncWithErrorHandling(["reset", "--hard", "origin/main"], cwd: repoURL)
      if !reset.success {
        await MainActor.run {
          self.syncConflictLastError = reset.error?.errorDescription ?? "Reset failed"
          self.flashError(self.syncConflictLastError ?? "Sync recovery failed")
          self.isGitBusy = false
        }
        return
      }

      // Best-effort pop (may fail if there was nothing to stash)
      _ = await Git.runAsyncWithErrorHandling(["stash", "pop"], cwd: repoURL)

      let add = await Git.runAsyncWithErrorHandling(["add", "-A"], cwd: repoURL)
      if !add.success {
        await MainActor.run {
          self.syncConflictLastError = add.error?.errorDescription ?? "Failed to stage changes"
          self.flashError(self.syncConflictLastError ?? "Sync recovery failed")
          self.isGitBusy = false
        }
        return
      }

      let author = "Lobs <thelobsbot@gmail.com>"
      let committerEnv: [String: String] = [
        "GIT_COMMITTER_NAME": "Lobs",
        "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
      ]
      let commit = await Git.runAsyncWithErrorHandling(
        ["commit", "--author", author, "-m", "Sync recovery: keep local changes"],
        cwd: repoURL,
        env: committerEnv
      )
      if !commit.success {
        await MainActor.run {
          self.syncConflictLastError = commit.error?.errorDescription ?? "Commit failed"
          self.flashError(self.syncConflictLastError ?? "Sync recovery failed")
          self.isGitBusy = false
        }
        return
      }

      let push = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
      if !push.success {
        await MainActor.run {
          self.syncConflictLastError = push.error?.errorDescription ?? "Push failed"
          self.lastPushError = self.syncConflictLastError
          self.flashError(self.syncConflictLastError ?? "Push failed")
          self.isGitBusy = false
        }
        return
      }

      await MainActor.run {
        self.syncBlockedByUncommitted = false
        self.syncConflictDetailsPresented = false
        self.syncConflictFiles = []
        self.flashSuccess("Recovered sync: kept local changes")
        self.isGitBusy = false
        self.reload()
      }
    }
  }

  /// Option 2: Use Remote Version
  /// - Abort any in-progress rebase
  /// - Reset hard to origin/main
  /// - Clean untracked
  /// - Reload from disk
  func recoverSyncConflictUseRemote() {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    syncConflictLastError = nil

    Task {
      _ = await Git.runAsyncWithErrorHandling(["rebase", "--abort"], cwd: repoURL)

      let fetch = await Git.runAsyncWithErrorHandling(["fetch", "origin"], cwd: repoURL)
      if !fetch.success {
        await MainActor.run {
          self.syncConflictLastError = fetch.error?.errorDescription ?? "Fetch failed"
          self.flashError(self.syncConflictLastError ?? "Sync recovery failed")
          self.isGitBusy = false
        }
        return
      }

      let reset = await Git.runAsyncWithErrorHandling(["reset", "--hard", "origin/main"], cwd: repoURL)
      if !reset.success {
        await MainActor.run {
          self.syncConflictLastError = reset.error?.errorDescription ?? "Reset failed"
          self.flashError(self.syncConflictLastError ?? "Sync recovery failed")
          self.isGitBusy = false
        }
        return
      }

      _ = await Git.runAsyncWithErrorHandling(["clean", "-fd"], cwd: repoURL)

      await MainActor.run {
        self.syncBlockedByUncommitted = false
        self.syncConflictDetailsPresented = false
        self.syncConflictFiles = []
        self.flashSuccess("Recovered sync: using remote version")
        self.isGitBusy = false
        self.reload()
      }
    }
  }

  // MARK: - Rebase Recovery

  /// Check whether the repo is currently in a stuck/in-progress rebase state.
  ///
  /// This detects the common on-disk markers Git uses:
  /// - .git/rebase-merge
  /// - .git/rebase-apply
  func checkRebaseState() -> RebaseState {
    guard let repoURL else { return .none }
    return checkRebaseState(repoURL: repoURL)
  }

  private func checkRebaseState(repoURL: URL) -> RebaseState {
    guard let gitDir = gitDirURL(for: repoURL) else { return .none }

    let fm = FileManager.default
    let merge = gitDir.appendingPathComponent("rebase-merge")
    let apply = gitDir.appendingPathComponent("rebase-apply")
    guard fm.fileExists(atPath: merge.path) || fm.fileExists(atPath: apply.path) else {
      return .none
    }

    // Attempt to detect conflicted files (unmerged paths).
    // If the command fails, still treat it as "needsResolution" so we can present recovery UI.
    let res = Git.runWithErrorHandling(["diff", "--name-only", "--diff-filter=U"], cwd: repoURL)
    guard res.success else {
      return .needsResolution
    }

    let files = res.output
      .split(separator: "\n")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    return .inProgress(conflictFiles: files)
  }

  /// Present the rebase recovery dialog if a rebase is currently in progress.
  /// Call this on startup and before git operations.
  private func promptRebaseRecoveryIfNeeded(context: String) {
    let state = checkRebaseState()
    guard case .none = state else {
      switch state {
      case .inProgress(let files):
        rebaseRecoveryConflictFiles = files
      case .needsResolution:
        rebaseRecoveryConflictFiles = []
      case .none:
        break
      }
      rebaseRecoveryLastError = nil
      syncConflictLastError = nil
      syncBlockedByUncommitted = true
      rebaseRecoveryPresented = true
      print("[rebase] Recovery prompt shown (context: \(context))")
      return
    }
  }

  var rebaseRecoveryDialogMessage: String {
    if let err = rebaseRecoveryLastError, !err.isEmpty {
      return err
    }

    if !rebaseRecoveryConflictFiles.isEmpty {
      let preview = rebaseRecoveryConflictFiles.prefix(6).joined(separator: "\n")
      let more = rebaseRecoveryConflictFiles.count > 6 ? "\n… (+\(rebaseRecoveryConflictFiles.count - 6) more)" : ""
      return "A git rebase is currently in progress and has unresolved conflicts:\n\n\(preview)\(more)"
    }

    return "A git rebase is currently in progress. If you already resolved conflicts, choose Continue Rebase. Otherwise you can Abort or Skip the current commit."
  }

  func rebaseRecoveryContinue() {
    runRebaseRecoveryCommand(["rebase", "--continue"], successMessage: "Rebase continued")
  }

  func rebaseRecoveryAbort() {
    runRebaseRecoveryCommand(["rebase", "--abort"], successMessage: "Rebase aborted")
  }

  func rebaseRecoverySkip() {
    runRebaseRecoveryCommand(["rebase", "--skip"], successMessage: "Rebase skipped")
  }

  private func runRebaseRecoveryCommand(_ args: [String], successMessage: String) {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    rebaseRecoveryLastError = nil

    Task {
      let res = await Git.runAsyncWithErrorHandling(args, cwd: repoURL)

      if !res.success {
        let files = await self.loadCurrentConflictFiles(repoURL: repoURL)
        await MainActor.run {
          self.rebaseRecoveryConflictFiles = files
          self.rebaseRecoveryLastError = res.error?.errorDescription ?? "Git operation failed"
          self.syncBlockedByUncommitted = true
          self.flashError(self.rebaseRecoveryLastError ?? "Git operation failed")
          // If there are conflicts, offer the per-file resolution sheet.
          if !files.isEmpty {
            self.syncConflictFiles = files
            self.syncConflictDetailsPresented = true
          }
          self.isGitBusy = false
        }
        return
      }

      // Command succeeded. If the rebase is still in progress, keep the dialog open and refresh state.
      let stateAfter = await MainActor.run { self.checkRebaseState(repoURL: repoURL) }
      await MainActor.run {
        switch stateAfter {
        case .none:
          self.rebaseRecoveryPresented = false
          self.rebaseRecoveryConflictFiles = []
          self.syncBlockedByUncommitted = false
          self.flashSuccess(successMessage)
          self.isGitBusy = false
          self.reload()
        case .inProgress(let files):
          self.rebaseRecoveryConflictFiles = files
          self.syncBlockedByUncommitted = true
          self.rebaseRecoveryPresented = true
          self.flashSuccess(successMessage)
          self.isGitBusy = false
        case .needsResolution:
          self.rebaseRecoveryConflictFiles = []
          self.syncBlockedByUncommitted = true
          self.rebaseRecoveryPresented = true
          self.flashSuccess(successMessage)
          self.isGitBusy = false
        }
      }
    }
  }

  private func gitDirURL(for repoURL: URL) -> URL? {
    let dotGit = repoURL.appendingPathComponent(".git")
    var isDir: ObjCBool = false

    // Standard layout: .git is a directory
    if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir), isDir.boolValue {
      return dotGit
    }

    // Worktrees/submodules: .git is a file containing "gitdir: <path>"
    if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir), !isDir.boolValue {
      if let content = try? String(contentsOf: dotGit, encoding: .utf8) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("gitdir:") {
          let pathPart = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
          let gitdirPath = String(pathPart)
          let resolved: URL
          if gitdirPath.hasPrefix("/") {
            resolved = URL(fileURLWithPath: gitdirPath)
          } else {
            resolved = repoURL.appendingPathComponent(gitdirPath)
          }
          return resolved
        }
      }
    }

    return nil
  }

  /// Option 3: Show details / per-file resolution.
  /// Attempts a rebase and (if it conflicts) leaves the rebase in-progress so the user can resolve per-file.
  func showSyncConflictDetails() {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    syncConflictLastError = nil

    Task {
      let fetch = await Git.runAsyncWithErrorHandling(["fetch", "origin"], cwd: repoURL)
      if !fetch.success {
        await MainActor.run {
          self.syncConflictLastError = fetch.error?.errorDescription ?? "Fetch failed"
          self.flashError(self.syncConflictLastError ?? "Failed to fetch")
          self.isGitBusy = false
        }
        return
      }

      let rebase = await Git.runAsyncWithErrorHandling(["rebase", "origin/main"], cwd: repoURL)
      if rebase.success {
        await MainActor.run {
          self.syncBlockedByUncommitted = false
          self.syncConflictDetailsPresented = false
          self.syncConflictFiles = []
          self.flashSuccess("Sync conflict resolved")
          self.isGitBusy = false
          self.reload()
        }
        return
      }

      // Rebase conflicted; keep it in-progress for the details UI.
      let files = await self.loadCurrentConflictFiles(repoURL: repoURL)
      await MainActor.run {
        self.syncBlockedByUncommitted = true
        self.syncConflictFiles = files
        self.syncConflictDetailsPresented = true
        self.syncConflictLastError = rebase.error?.errorDescription
        self.isGitBusy = false
      }
    }
  }

  func syncConflictResolveFileKeepingMine(_ path: String) {
    syncConflictResolveFile(path, useTheirs: false)
  }

  func syncConflictResolveFileUsingRemote(_ path: String) {
    syncConflictResolveFile(path, useTheirs: true)
  }

  private func syncConflictResolveFile(_ path: String, useTheirs: Bool) {
    guard let repoURL else { return }
    guard !isGitBusy else { return }

    isGitBusy = true
    syncConflictLastError = nil

    Task {
      let checkoutArgs = useTheirs
        ? ["checkout", "--theirs", "--", path]
        : ["checkout", "--ours", "--", path]
      let checkout = await Git.runAsyncWithErrorHandling(checkoutArgs, cwd: repoURL)
      if !checkout.success {
        await MainActor.run {
          self.syncConflictLastError = checkout.error?.errorDescription ?? "Failed to update file"
          self.flashError(self.syncConflictLastError ?? "Resolve failed")
          self.isGitBusy = false
        }
        return
      }

      let add = await Git.runAsyncWithErrorHandling(["add", "--", path], cwd: repoURL)
      if !add.success {
        await MainActor.run {
          self.syncConflictLastError = add.error?.errorDescription ?? "Failed to stage file"
          self.flashError(self.syncConflictLastError ?? "Resolve failed")
          self.isGitBusy = false
        }
        return
      }

      let files = await self.loadCurrentConflictFiles(repoURL: repoURL)
      await MainActor.run {
        self.syncConflictFiles = files
        self.isGitBusy = false
      }
    }
  }

  func syncConflictContinueRebase() {
    guard let repoURL else { return }
    guard !isGitBusy else { return }

    isGitBusy = true
    syncConflictLastError = nil

    Task {
      let cont = await Git.runAsyncWithErrorHandling(["rebase", "--continue"], cwd: repoURL)
      if cont.success {
        // Either finished, or moved to next commit.
        let files = await self.loadCurrentConflictFiles(repoURL: repoURL)
        await MainActor.run {
          self.syncConflictFiles = files
          if files.isEmpty {
            self.syncBlockedByUncommitted = false
            self.syncConflictDetailsPresented = false
            self.flashSuccess("Rebase complete")
            self.reload()
          }
          self.isGitBusy = false
        }
        return
      }

      // Still conflicted.
      let files = await self.loadCurrentConflictFiles(repoURL: repoURL)
      await MainActor.run {
        self.syncConflictFiles = files
        self.syncBlockedByUncommitted = true
        self.syncConflictLastError = cont.error?.errorDescription
        self.isGitBusy = false
      }
    }
  }

  func syncConflictAbortRebase() {
    guard let repoURL else { return }
    guard !isGitBusy else { return }

    isGitBusy = true
    syncConflictLastError = nil

    Task {
      _ = await Git.runAsyncWithErrorHandling(["rebase", "--abort"], cwd: repoURL)
      await MainActor.run {
        self.syncConflictFiles = []
        self.syncConflictDetailsPresented = false
        self.syncBlockedByUncommitted = false
        self.isGitBusy = false
        self.flashSuccess("Rebase aborted")
        self.reload()
      }
    }
  }

  func syncConflictRefreshFiles() {
    guard let repoURL else { return }
    Task {
      let files = await self.loadCurrentConflictFiles(repoURL: repoURL)
      await MainActor.run {
        self.syncConflictFiles = files
      }
    }
  }

  private func loadCurrentConflictFiles(repoURL: URL) async -> [String] {
    let diff = await Git.runAsyncWithErrorHandling(["diff", "--name-only", "--diff-filter=U"], cwd: repoURL)
    if diff.success {
      return diff.output
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // Fallback: parse git status for unmerged entries
    let status = await Git.runAsyncWithErrorHandling(["status", "--porcelain"], cwd: repoURL)
    guard status.success else { return [] }

    // Unmerged lines usually start with UU/AA/DU/UD/etc.
    return status.output
      .split(separator: "\n")
      .map(String.init)
      .compactMap { line in
        guard line.count >= 4 else { return nil }
        let prefix = line.prefix(2)
        if prefix.contains("U") || prefix == "AA" || prefix == "DD" {
          return String(line.dropFirst(3))
        }
        return nil
      }
  }

  /// Refresh per-project last git commit times by querying the lobs-control git history for
  /// files that belong to each project (project folder + its task JSON files).
  func refreshProjectLastCommitAt() {
    guard let repoURL else { return }

    let projectsSnapshot = projects
    let tasksSnapshot = tasks

    Task.detached(priority: .utility) {
      let fm = FileManager.default
      var out: [String: Date] = [:]

      for project in projectsSnapshot {
        let pid = project.id
        let projectTasks = tasksSnapshot.filter { ($0.projectId ?? "default") == pid }

        var maxCT: Int64? = nil

        // Include the per-project folder (research docs, etc) if it exists.
        let projectDirRel = "state/projects/\(pid)"
        let projectDirAbs = repoURL.appendingPathComponent(projectDirRel).path
        var candidatePaths: [String] = []
        if fm.fileExists(atPath: projectDirAbs) {
          candidatePaths.append(projectDirRel)
        }

        // Include each task JSON file for the project.
        candidatePaths += projectTasks.map { "state/tasks/\($0.id).json" }

        // Always include projects.json since it contains the project metadata (title, notes, etc).
        candidatePaths.append("state/projects.json")

        for rel in candidatePaths {
          do {
            let res = try await Git.runAsync(["log", "-1", "--format=%ct", "--", rel], cwd: repoURL)
            guard res.ok else { continue }
            let s = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let ct = Int64(s) else { continue }
            if maxCT == nil || ct > maxCT! {
              maxCT = ct
            }
          } catch {
            continue
          }
        }

        if let maxCT {
          out[pid] = Date(timeIntervalSince1970: TimeInterval(maxCT))
        }
      }

      await MainActor.run {
        self.projectLastCommitAt = out
      }
    }
  }

  func loadResearchData() {
    guard isResearchProject else {
      researchTiles = []
      researchRequests = []
      researchDocContent = ""
      researchSources = []
      researchDeliverables = []
      // Stop polling for research if not a research project
      pollingManager.stopResearchPolling(projectId: selectedProjectId)
      return
    }
    
    // Start polling for research data
    pollingManager.startResearchPolling(projectId: selectedProjectId)
    
    // Update local state from cache
    researchDocContent = cache.getResearchDoc(selectedProjectId) ?? ""
    researchSources = cache.getResearchSources(selectedProjectId)
    researchRequests = cache.getResearchRequests(selectedProjectId)
    
    // Legacy tiles (not used anymore but keep for compatibility)
    researchTiles = []
  }

  // MARK: - Agent Documents (Reports & Research)

  func loadAgentDocuments() {
    Task {
      do {
        var docs = try await api.loadAgentDocuments()
        // Apply read state
        for i in docs.indices {
          docs[i].isRead = readDocumentIds.contains(docs[i].id)
        }
        await MainActor.run {
          self.agentDocuments = docs
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to load agent documents: \(error.localizedDescription)")
        }
      }
    }
  }

  func markDocumentRead(_ doc: AgentDocument) {
    readDocumentIds.insert(doc.id)
    if let idx = agentDocuments.firstIndex(where: { $0.id == doc.id }) {
      agentDocuments[idx].isRead = true
    }
  }

  func markDocumentUnread(_ doc: AgentDocument) {
    readDocumentIds.remove(doc.id)
    if let idx = agentDocuments.firstIndex(where: { $0.id == doc.id }) {
      agentDocuments[idx].isRead = false
    }
  }

  // MARK: - Research Document Actions

  func saveResearchDocContent(_ content: String) {
    researchDocContent = content

    Task {
      do {
        try await api.saveResearchDoc(projectId: selectedProjectId, content: content)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save research doc: \(error.localizedDescription)")
        }
      }
    }
  }

  func saveResearchDeliverableContent(filename: String, content: String) {
    // Update local cache
    if let idx = researchDeliverables.firstIndex(where: { $0.filename == filename }) {
      researchDeliverables[idx].content = content
      researchDeliverables[idx].modifiedAt = Date()
    }

    Task {
      do {
        try await api.saveResearchDeliverable(projectId: selectedProjectId, filename: filename, content: content)
        // Reload deliverables to get updated timestamps from server
        let deliverables = try await api.loadResearchDeliverables(projectId: selectedProjectId)
        await MainActor.run {
          self.researchDeliverables = deliverables
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save research deliverable: \(error.localizedDescription)")
        }
      }
    }
  }

  func addResearchSource(url: String, title: String, tags: [String]? = nil) {
    let source = ResearchSource(
      id: UUID().uuidString,
      url: url,
      title: title,
      tags: tags,
      addedAt: Date()
    )
    researchSources.append(source)

    Task {
      do {
        try await api.addResearchSource(projectId: selectedProjectId, source: source)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save source: \(error.localizedDescription)")
        }
      }
    }
  }

  func removeResearchSource(id: String) {
    let projectId = selectedProjectId
    
    researchSources.removeAll { $0.id == id }
    
    Task {
      do {
        try await apiService?.deleteResearchSource(projectId: projectId, sourceId: id)
      } catch {
        await MainActor.run {
          flashError("Failed to delete research source: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Tracker

  func loadTrackerData() {
    guard isTrackerProject else {
      trackerItems = []
      trackerRequests = []
      // Stop polling for tracker if not a tracker project
      pollingManager.stopTrackerPolling(projectId: selectedProjectId)
      return
    }
    
    // Start polling for tracker data
    pollingManager.startTrackerPolling(projectId: selectedProjectId)
    
    // Update local state from cache
    trackerItems = cache.getTrackerItems(selectedProjectId)
    trackerRequests = cache.getResearchRequests(selectedProjectId)
  }

  func addTrackerItem(title: String, difficulty: String? = nil, tags: [String]? = nil, notes: String? = nil, links: [String]? = nil) {
    let now = Date()
    let item = TrackerItem(
      id: UUID().uuidString,
      projectId: selectedProjectId,
      title: title,
      status: .notStarted,
      difficulty: difficulty,
      tags: tags,
      notes: notes,
      links: links,
      createdAt: now,
      updatedAt: now
    )

    trackerItems.append(item)

    Task {
      do {
        try await api.addTrackerItem(projectId: selectedProjectId, item: item)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save tracker item: \(error.localizedDescription)")
        }
      }
    }
  }

  func updateTrackerItem(_ item: TrackerItem) {
    var updated = item
    updated.updatedAt = Date()

    if let idx = trackerItems.firstIndex(where: { $0.id == item.id }) {
      trackerItems[idx] = updated
    }

    Task {
      do {
        try await api.updateTrackerItem(projectId: selectedProjectId, itemId: updated.id, item: updated)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save tracker item: \(error.localizedDescription)")
        }
      }
    }
  }

  func removeTrackerItem(_ item: TrackerItem) {
    trackerItems.removeAll { $0.id == item.id }

    Task {
      do {
        try await api.deleteTrackerItem(projectId: item.projectId, itemId: item.id)
      } catch {
        await MainActor.run {
          self.flashError("Failed to delete tracker item: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Tracker Requests (Ask Lobs)

  func addTrackerRequest(prompt: String) {
    let now = Date()
    let req = ResearchRequest(
      id: UUID().uuidString,
      projectId: selectedProjectId,
      tileId: nil,
      prompt: prompt,
      status: .open,
      response: nil,
      author: "rafe",
      createdAt: now,
      updatedAt: now
    )

    trackerRequests.insert(req, at: 0)

    Task {
      do {
        try await api.addResearchRequest(projectId: selectedProjectId, request: req)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save tracker request: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Inbox

  private func applyInboxReadStateFromRepo() {
    // Read state is now persisted server-side via is_read field
    // This method kept for compatibility but is no longer needed
  }

  private func persistInboxReadStateDebounced() {
    // Persist inbox read state to server
    Task {
      do {
        try await apiService?.saveInboxReadState(
          readItemIds: inboxReadItemIds,
          lastSeenThreadCounts: inboxLastSeenThreadCounts
        )
      } catch {
        // Silent fail - read state persistence is non-critical
        print("Failed to persist inbox read state: \(error)")
      }
    }
  }

  func loadInboxItems() {
    Task {
      do {
        var items = try await api.loadInboxItems()
        // Apply read state from local settings
        for i in items.indices {
          items[i].isRead = readItemIds.contains(items[i].id)
        }
        
        // Load threads
        var loadedThreads: [String: InboxThread] = [:]
        for item in items {
          if let thread = try? await api.loadInboxThread(docId: item.id) {
            loadedThreads[item.id] = thread
          }
        }
        
        // Merge back any threads with pending local writes
        for (docId, pendingThread) in pendingThreadWrites {
          if let serverThread = loadedThreads[docId] {
            // Keep the pending version if it's newer
            if pendingThread.updatedAt >= serverThread.updatedAt {
              loadedThreads[docId] = pendingThread
            } else {
              // Server version is newer — drop pending
              await MainActor.run {
                self.pendingThreadWrites.removeValue(forKey: docId)
              }
            }
          } else {
            // Thread only exists locally
            loadedThreads[docId] = pendingThread
          }
        }
        
        // Update counts for sentinel values
        var updatedSeen = await lastSeenThreadCounts
        var didChangeSeen = false
        for (docId, thread) in loadedThreads {
          if updatedSeen[docId] == -1 {
            updatedSeen[docId] = thread.messages.count
            didChangeSeen = true
          }
        }
        
        await MainActor.run {
          self.inboxItems = items
          self.inboxThreadsByDocId = loadedThreads
          if didChangeSeen {
            self.lastSeenThreadCounts = updatedSeen
          }
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to load inbox: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Returns how many follow-up thread messages are currently unread for a doc.
  /// A follow-up is considered unread when the thread has more messages than the
  /// last-seen count recorded locally.
  func unreadFollowupCount(docId: String) -> Int {
    guard let thread = inboxThreadsByDocId[docId] else { return 0 }
    let seen = lastSeenThreadCounts[docId, default: 0]

    // If we marked this thread as "seen" before the thread content was loaded,
    // we store a sentinel of -1. Treat it as fully seen.
    if seen < 0 { return 0 }

    return max(0, thread.messages.count - seen)
  }

  func markInboxItemRead(_ item: InboxItem) {
    readItemIds.insert(item.id)
    if let idx = inboxItems.firstIndex(where: { $0.id == item.id }) {
      inboxItems[idx].isRead = true
    }
    // Mark thread follow-ups as seen when opening/marking as read.
    // If thread data hasn't been loaded yet, record a sentinel so that when
    // the thread arrives we don't briefly show the item as unread again.
    if let thread = inboxThreadsByDocId[item.id] {
      lastSeenThreadCounts[item.id] = thread.messages.count
    } else {
      lastSeenThreadCounts[item.id] = -1
    }
  }

  func markInboxItemUnread(_ item: InboxItem) {
    readItemIds.remove(item.id)
    if let idx = inboxItems.firstIndex(where: { $0.id == item.id }) {
      inboxItems[idx].isRead = false
    }
    // Do not change lastSeenThreadCounts here.
  }

  func markAllInboxItemsAsRead() {
    for item in inboxItems where !item.isRead {
      markInboxItemRead(item)
    }
  }

  /// If the inbox item's content was loaded as a preview, load the full file contents.
  /// This keeps background sync + list rendering fast, but still shows the full doc
  /// when the user selects it.
  func ensureInboxItemContentLoaded(docId: String) {
    guard let repoURL else { return }
    guard let idx = inboxItems.firstIndex(where: { $0.id == docId }) else { return }
    guard inboxItems[idx].contentIsTruncated else { return }

    let relativePath = inboxItems[idx].relativePath
    let expectedModifiedAt = inboxItems[idx].modifiedAt

    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      let fileURL = repoURL.appendingPathComponent(relativePath)
      let full = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
      await MainActor.run {
        guard let liveIdx = self.inboxItems.firstIndex(where: { $0.id == docId }) else { return }
        // Avoid overwriting if the item changed (e.g. sync pulled a newer version).
        guard self.inboxItems[liveIdx].modifiedAt == expectedModifiedAt else { return }
        self.inboxItems[liveIdx].content = full
        self.inboxItems[liveIdx].contentIsTruncated = false
      }
    }
  }

  /// Total unread inbox count.
  /// Includes unread docs AND docs with unread follow-up thread messages.
  /// Only counts actual inbox items from inbox/ (not state/inbox/, not artifacts) to match what InboxView displays.
  var unreadInboxCount: Int {
    inboxItems.filter { item in
      item.relativePath.hasPrefix("inbox/") &&
      (!item.isRead || unreadFollowupCount(docId: item.id) > 0)
    }.count
  }

  // REMOVED: inboxResponseText() - dead code (never called), replaced by inboxThreadsByDocId

  func saveInboxResponse(docId: String, response: String) {
    Task {
      do {
        let thread = try await api.saveInboxResponse(docId: docId, response: response)
        await MainActor.run {
          self.inboxThreadsByDocId[docId] = thread
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save inbox response: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Project README

  func loadProjectReadme() {
    // For API mode, project notes are the only source (no separate README file)
    projectReadme = projects.first(where: { $0.id == selectedProjectId })?.notes ?? ""
  }

  func saveProjectReadme(content: String) {
    projectReadme = content

    // Keep project notes in sync with README (they are the same content)
    let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if let idx = projects.firstIndex(where: { $0.id == selectedProjectId }) {
      projects[idx].notes = clean.isEmpty ? nil : clean
      projects[idx].updatedAt = Date()
    }

    Task {
      do {
        try await api.saveProjectReadme(projectId: selectedProjectId, content: content)
        try await api.updateProjectNotes(id: selectedProjectId, notes: clean.isEmpty ? nil : clean)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save README: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Task Templates

  // MARK: - Worker Status

  func loadWorkerStatus() {
    Task {
      do {
        let oldStatus = await MainActor.run { workerStatus }
        let newStatus = try await api.loadWorkerStatus()
        let history = try await api.loadWorkerHistory()
        
        await MainActor.run {
          self.workerStatus = newStatus
          self.workerHistory = history
          self.mainSessionUsage = nil
        }

        // Detect worker state changes and send macOS notifications
        if let old = oldStatus, let new = newStatus {
          // Worker finished (was active, now inactive)
          if old.active && !new.active {
            let count = new.tasksCompleted ?? 0
            sendSystemNotification(
              title: "Worker Finished",
              body: "Completed \(count) task\(count == 1 ? "" : "s")."
            )
          }
          // Worker completed a new task (task count increased)
          else if old.active && new.active,
                  let oldCount = old.tasksCompleted, let newCount = new.tasksCompleted,
                  newCount > oldCount {
            let taskName = new.currentTask ?? "a task"
            sendSystemNotification(
              title: "Task Completed",
              body: "Finished: \(taskName). (\(newCount) total)"
            )
          }
          // Worker started (was inactive, now active)
          else if !old.active && new.active {
            sendSystemNotification(
              title: "Worker Started",
              body: new.currentTask.map { "Working on: \($0)" } ?? "Worker is now active."
            )
          }
        }
      } catch {
        await MainActor.run {
          self.workerStatus = nil
        }
      }
    }
  }


  /// Request notification permissions on first use.
  func requestNotificationPermissions() {
    guard Bundle.main.bundleIdentifier != nil else { return }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
  }

  private func sendSystemNotification(title: String, body: String) {
    guard Bundle.main.bundleIdentifier != nil else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil // deliver immediately
    )
    UNUserNotificationCenter.current().add(request) { _ in }
  }

  @Published var templates: [TaskTemplate] = []

  func loadTemplates() {
    Task {
      do {
        let templates = try await api.loadTemplates()
        await MainActor.run {
          self.templates = templates
        }
      } catch {
        await MainActor.run {
          self.templates = []
        }
      }
    }
  }

  func saveTemplate(_ template: TaskTemplate) {
    if let idx = templates.firstIndex(where: { $0.id == template.id }) {
      templates[idx] = template
    } else {
      templates.append(template)
    }

    Task {
      do {
        try await api.saveTemplate(template)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save template: \(error.localizedDescription)")
        }
      }
    }
  }

  func deleteTemplate(id: String) {
    templates.removeAll { $0.id == id }

    Task {
      do {
        try await api.deleteTemplate(id: id)
      } catch {
        await MainActor.run {
          self.flashError("Failed to delete template: \(error.localizedDescription)")
        }
      }
    }
  }

  func stampTemplate(_ template: TaskTemplate, autoPush: Bool) {
    let now = Date()

    var newTasks: [DashboardTask] = []
    for item in template.items {
      let task = DashboardTask(
        id: UUID().uuidString,
        title: item.title,
        status: .active,
        owner: .lobs,
        createdAt: now,
        updatedAt: now,
        workState: .notStarted,
        reviewState: .approved,
        projectId: selectedProjectId,
        artifactPath: nil,
        notes: item.notes,
        startedAt: now,
        finishedAt: nil
      )
      newTasks.append(task)
    }

    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      tasks.append(contentsOf: newTasks)
    }

    // Check if the selected project uses GitHub tracking
    let project = projects.first(where: { $0.id == selectedProjectId })
    let isGitHubProject = project?.resolvedTracking == .github
    let githubConfig = project?.github

    Task {
      do {
        // Create tasks via API
        for task in newTasks {
          let _ = try await api.addTask(
            id: task.id,
            title: task.title,
            owner: task.owner,
            status: task.status,
            projectId: task.projectId,
            workState: task.workState,
            reviewState: task.reviewState,
            notes: task.notes
          )
        }
        
        // For GitHub projects, create issues for each task
        if isGitHubProject, let config = githubConfig {
          var issueNumbers: [String: Int] = [:]
          
          for task in newTasks {
            do {
              let issueNumber = try await createGitHubIssue(
                repo: config.repo,
                title: task.title,
                body: task.notes ?? "",
                labels: config.labelFilter
              )
              issueNumbers[task.id] = issueNumber
              
              // Update task in memory
              await MainActor.run {
                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                  self.tasks[idx].githubIssueNumber = issueNumber
                }
              }
              
              // Update task with GitHub issue number
              var updatedTask = task
              updatedTask.githubIssueNumber = issueNumber
              try await api.saveExistingTask(updatedTask)
            } catch {
              await MainActor.run {
                self.flashError("Failed to create GitHub issue for '\(task.title)': \(error.localizedDescription)")
              }
            }
          }
          
          await MainActor.run {
            self.flashSuccess("Created \(issueNumbers.count) GitHub issues")
            self.silentReload()
          }
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to create tasks from template: \(error.localizedDescription)")
        }
      }
    }
  }

  func postInboxThreadMessage(docId: String, author: String, text: String) {
    let now = Date()
    let msg = InboxThreadMessage(
      id: UUID().uuidString,
      author: author,
      text: text,
      createdAt: now
    )

    // Update in-memory thread optimistically
    if var thread = inboxThreadsByDocId[docId] {
      thread.messages.append(msg)
      thread.updatedAt = now
      inboxThreadsByDocId[docId] = thread
    } else {
      // Create new thread
      let thread = InboxThread(
        id: UUID().uuidString,
        docId: docId,
        messages: [msg],
        createdAt: now,
        updatedAt: now
      )
      inboxThreadsByDocId[docId] = thread
    }

    // If the user just posted (e.g. author=="rafe"), consider the thread fully read.
    if author.lowercased() == "rafe", let thread = inboxThreadsByDocId[docId] {
      lastSeenThreadCounts[docId] = thread.messages.count
    }

    // Track as pending so auto-refresh won't overwrite it with stale data
    if let thread = inboxThreadsByDocId[docId] {
      pendingThreadWrites[docId] = thread
    }

    Task {
      do {
        let updatedThread = try await api.saveInboxThread(inboxThreadsByDocId[docId]!)
        await MainActor.run {
          self.inboxThreadsByDocId[docId] = updatedThread
          self.pendingThreadWrites.removeValue(forKey: docId)
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save thread: \(error.localizedDescription)")
        }
      }
    }
  }

  func editInboxThreadMessage(docId: String, messageId: String, newText: String) {
    guard var thread = inboxThreadsByDocId[docId],
          let idx = thread.messages.firstIndex(where: { $0.id == messageId }) else { return }

    thread.messages[idx] = InboxThreadMessage(
      id: messageId,
      author: thread.messages[idx].author,
      text: newText,
      createdAt: thread.messages[idx].createdAt
    )
    thread.updatedAt = Date()
    inboxThreadsByDocId[docId] = thread

    // Track as pending so auto-refresh won't overwrite it with stale data
    pendingThreadWrites[docId] = thread

    Task {
      do {
        let updatedThread = try await api.saveInboxThread(thread)
        await MainActor.run {
          self.inboxThreadsByDocId[docId] = updatedThread
          self.pendingThreadWrites.removeValue(forKey: docId)
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save thread: \(error.localizedDescription)")
        }
      }
    }
  }

  func deleteInboxThreadMessage(docId: String, messageId: String) {
    guard var thread = inboxThreadsByDocId[docId],
          let idx = thread.messages.firstIndex(where: { $0.id == messageId }) else { return }

    thread.messages.remove(at: idx)
    thread.updatedAt = Date()
    inboxThreadsByDocId[docId] = thread

    // Track as pending so auto-refresh won't overwrite it with stale data
    pendingThreadWrites[docId] = thread

    Task {
      do {
        let updatedThread = try await api.saveInboxThread(thread)
        await MainActor.run {
          self.inboxThreadsByDocId[docId] = updatedThread
          self.pendingThreadWrites.removeValue(forKey: docId)
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save thread: \(error.localizedDescription)")
        }
      }
    }
  }

  func updateInboxThreadTriage(docId: String, status: InboxTriageStatus) {
    guard var thread = inboxThreadsByDocId[docId] else { return }

    thread.triageStatus = status
    thread.updatedAt = Date()
    inboxThreadsByDocId[docId] = thread

    // Track as pending so auto-refresh won't overwrite it with stale data
    pendingThreadWrites[docId] = thread

    Task {
      do {
        let updatedThread = try await api.saveInboxThread(thread)
        await MainActor.run {
          self.inboxThreadsByDocId[docId] = updatedThread
          self.pendingThreadWrites.removeValue(forKey: docId)
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save thread: \(error.localizedDescription)")
        }
      }
    }
  }

  func quickReplyInboxThread(docId: String, reply: String, triageStatus: InboxTriageStatus) {
    // Post the message
    postInboxThreadMessage(docId: docId, author: "rafe", text: reply)

    // Update triage status
    guard var thread = inboxThreadsByDocId[docId] else { return }
    thread.triageStatus = triageStatus
    thread.updatedAt = Date()
    inboxThreadsByDocId[docId] = thread

    Task {
      do {
        let updatedThread = try await api.saveInboxThread(thread)
        await MainActor.run {
          self.inboxThreadsByDocId[docId] = updatedThread
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save thread: \(error.localizedDescription)")
        }
      }
    }
  }

  func selectTask(_ task: DashboardTask) {
    selectedTaskId = task.id
    loadArtifactForSelected()
  }

  // MARK: - Optimistic + Async Helpers

  /// Show error banner that auto-dismisses after a few seconds.
  func flashError(_ message: String) {
    errorBanner = message
    Task {
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      if errorBanner == message { errorBanner = nil }
    }
  }

  func flashSuccess(_ message: String) {
    successBanner = message
    Task {
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      if successBanner == message { successBanner = nil }
    }
  }

  // MARK: - Notification Management

  func postNotification(type: NotificationType, message: String) {
    // Check if this notification type is enabled
    guard notificationPreferences.enabledTypes.contains(type.rawValue) else { return }

    let notification = DashboardNotification(type: type, message: message)

    // High priority notifications show immediately
    if type.priority == .high {
      notifications.append(notification)
      return
    }

    // Low/medium priority notifications get batched if batching is enabled
    if notificationPreferences.batchLowPriority {
      batchedNotifications.append(notification)
      startBatchTimer()
    } else {
      notifications.append(notification)
    }
  }

  private func startBatchTimer() {
    // If timer is already running, don't start a new one
    guard batchTimer == nil else { return }

    batchTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(notificationPreferences.batchIntervalSeconds), repeats: false) { [weak self] _ in
      guard let self = self else { return }
      self.flushBatchedNotifications()
    }
  }

  private func flushBatchedNotifications() {
    guard !batchedNotifications.isEmpty else {
      batchTimer?.invalidate()
      batchTimer = nil
      return
    }

    // Add all batched notifications to the main queue
    notifications.append(contentsOf: batchedNotifications)
    batchedNotifications.removeAll()
    batchTimer?.invalidate()
    batchTimer = nil
  }

  func dismissNotification(id: String) {
    if let index = notifications.firstIndex(where: { $0.id == id }) {
      notifications[index].dismissed = true
      // Remove after a brief delay to allow animation
      Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        notifications.removeAll(where: { $0.id == id && $0.dismissed })
      }
    }
  }

  func dismissAllNotifications() {
    notifications.removeAll()
    batchedNotifications.removeAll()
    batchTimer?.invalidate()
    batchTimer = nil
  }

  func updateNotificationPreferences(_ preferences: NotificationPreferences) {
    notificationPreferences = preferences
    // Flush batched notifications if batching is disabled
    if !preferences.batchLowPriority {
      flushBatchedNotifications()
    }
  }

  /// Optimistically update a task locally, then persist via API in background.
  /// On failure, reload from server and show banner.
  private func optimisticUpdate(
    taskId: String,
    localMutation: (inout DashboardTask) -> Void,
    gitWork: @escaping (URL) async throws -> Void  // Keep signature for compatibility, URL is ignored
  ) {
    // 1. Apply local mutation immediately using cache (UI updates via binding)
    withAnimation(.easeInOut(duration: 0.25)) {
      cache.updateTask(taskId, update: localMutation)
    }

    // 2. Persist via API in background
    isGitBusy = true
    Task {
      do {
        if let task = cache.tasks.first(where: { $0.id == taskId }) {
          try await api.saveExistingTask(task)
        }
        cache.invalidateTasks()
      } catch {
        await MainActor.run {
          self.flashError("Failed to save: \(error.localizedDescription)")
          // Invalidate cache and force reload to get server state
          self.cache.invalidateTasks()
          Task {
            await self.pollingManager.refreshStaleData()
          }
        }
      }
      await MainActor.run {
        self.isGitBusy = false
      }
    }
  }

  // MARK: - Dependency Auto-Unblock

  /// When a task is completed, remove it from the `blockedBy` list of all dependent tasks.
  /// If a dependent task has no remaining blockers, auto-unblock it (set workState back from blocked).
  private func autoUnblockDependents(of completedTaskId: String, autoPush: Bool) {
    Task {
      for i in await tasks.indices {
        guard var blockers = await tasks[i].blockedBy, blockers.contains(completedTaskId) else { continue }
        blockers.removeAll { $0 == completedTaskId }
        
        await MainActor.run {
          self.tasks[i].blockedBy = blockers.isEmpty ? nil : blockers
          self.tasks[i].updatedAt = Date()

          // If no remaining blockers and task was blocked, unblock it
          if blockers.isEmpty && self.tasks[i].workState == .blocked {
            self.tasks[i].workState = .notStarted
          }
        }

        do {
          try await api.saveExistingTask(await tasks[i])
        } catch {
          await MainActor.run {
            self.flashError("Failed to save unblocked task: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  // MARK: - Actions (now optimistic + async)

  // MARK: - Context-Aware Task Actions
  //
  // Flow: Inbox → (approve) → Active → (complete) → Completed
  //       ↕ reject / request changes / reopen as needed

  /// Approve: sets reviewState=approved AND moves to Active.
  func approveSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.reviewState = .approved
      $0.status = .active
      $0.workState = .notStarted
      if $0.startedAt == nil { $0.startedAt = Date() }
    }) { _ in
      // Status change is persisted via optimisticUpdate → api.saveExistingTask
    }
  }

  func requestChangesSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: { $0.reviewState = .changesRequested }) { _ in }
  }

  func rejectSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.reviewState = .rejected
      $0.status = .rejected
    }) { _ in }
  }

  /// Mark an active task as completed (work is done).
  func completeSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.status = .completed
      $0.workState = nil
      if $0.finishedAt == nil { $0.finishedAt = Date() }
    }) { _ in }
    autoUnblockDependents(of: id, autoPush: autoPush)
  }

  /// Mark a completed task as Done (approved).
  /// This does not change workflow `status` (it stays `.completed`) — it sets `reviewState=approved`.
  func markDoneSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.status = .completed
      $0.reviewState = .approved
      $0.workState = nil
    }) { _ in }
  }

  /// Reopen a completed/rejected task back to Active.
  func reopenSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.status = .active
      $0.workState = .notStarted
      $0.reviewState = .approved
    }) { _ in }
  }

  /// Toggle blocked state on an active task.
  func toggleBlockSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    let currentlyBlocked = tasks.first(where: { $0.id == id })?.workState == .blocked
    let newState: WorkState = currentlyBlocked ? .inProgress : .blocked
    optimisticUpdate(taskId: id, localMutation: { $0.workState = newState }) { _ in }
  }

  func submitTaskToLobs(title: String, notes: String?, agent: String?, autoPush: Bool) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }

    // Check if the selected project uses GitHub tracking
    let project = projects.first(where: { $0.id == selectedProjectId })
    let isGitHubProject = project?.resolvedTracking == .github
    let githubConfig = project?.github

    // UX: when Rafe creates a task, that means "start work" → goes straight to Active.
    let now = Date()
    var newTask = DashboardTask(
      id: UUID().uuidString,
      title: trimmedTitle,
      status: .active,
      owner: .lobs,
      createdAt: now,
      updatedAt: now,
      workState: .notStarted,
      reviewState: .approved,
      projectId: selectedProjectId,
      artifactPath: nil,
      notes: trimmedNotes,
      startedAt: now,
      finishedAt: nil,
      agent: agent
    )

    // For GitHub projects, create the issue first and get the issue number
    if isGitHubProject, let config = githubConfig {
      // Show loading state in UI immediately
      withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        tasks.append(newTask)
        sortTasksForUX(&tasks)
      }
      selectedTaskId = newTask.id
      popoverTaskId = newTask.id
      
      isGitBusy = true
      Task {
        do {
          // Create GitHub issue and parse issue number
          let issueNumber = try await createGitHubIssue(
            repo: config.repo,
            title: trimmedTitle,
            body: trimmedNotes ?? "",
            labels: config.labelFilter
          )
          
          // Update task with GitHub issue number
          await MainActor.run {
            if let idx = self.tasks.firstIndex(where: { $0.id == newTask.id }) {
              self.tasks[idx].githubIssueNumber = issueNumber
            }
            newTask.githubIssueNumber = issueNumber
            self.flashSuccess("Created GitHub issue #\(issueNumber)")
          }
          
          // Save via API with GitHub issue number
          try await self.api.saveExistingTask(newTask)
          
          await MainActor.run {
            self.isGitBusy = false
            self.silentReload()
          }
        } catch {
          await MainActor.run {
            // Remove the task from UI since creation failed
            self.tasks.removeAll { $0.id == newTask.id }
            self.flashError("Failed to create GitHub issue: \(error.localizedDescription)")
            self.isGitBusy = false
          }
        }
      }
      return
    }

    // Local mode: standard flow
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      tasks.append(newTask)
      sortTasksForUX(&tasks)
    }

    // Ensure the newly-created task is selected for quick action.
    selectedTaskId = newTask.id
    popoverTaskId = newTask.id

    // Save via API
    isGitBusy = true
    Task {
      do {
        let savedTask = try await api.addTask(
          id: newTask.id,
          title: trimmedTitle,
          owner: .lobs,
          status: .active,
          projectId: selectedProjectId,
          workState: .notStarted,
          reviewState: .approved,
          notes: trimmedNotes
        )
        await MainActor.run {
          // Update with server response
          if let idx = self.tasks.firstIndex(where: { $0.id == newTask.id }) {
            self.tasks[idx] = savedTask
          }
          self.isGitBusy = false
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save task: \(error.localizedDescription)")
          self.isGitBusy = false
        }
      }
    }
  }
  
  /// Create a GitHub issue using gh CLI and return the issue number.
  private func createGitHubIssue(repo: String, title: String, body: String, labels: [String]?) async throws -> Int {
    // Build gh CLI command
    var args = ["issue", "create", "--repo", repo, "--title", title, "--body", body]
    
    // Add labels if provided
    if let labels = labels, !labels.isEmpty {
      for label in labels {
        args.append("--label")
        args.append(label)
      }
    }
    
    // Run gh CLI
    let result = try await runGhCommand(args: args)
    
    guard result.ok else {
      throw GitHubCLIError.commandFailed(stderr: result.stderr)
    }
    
    // Parse issue number from output
    // gh issue create outputs the issue URL, e.g., "https://github.com/owner/repo/issues/123"
    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let issueNumber = parseIssueNumberFromURL(output) else {
      throw GitHubCLIError.parseError(output: output)
    }
    
    return issueNumber
  }
  
  /// Run gh CLI command asynchronously.
  private func runGhCommand(args: [String]) async throws -> Git.Result {
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["gh"] + args
        proc.environment = ProcessInfo.processInfo.environment
        
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        
        do {
          try proc.run()
          proc.waitUntilExit()
          
          let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
          let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
          
          continuation.resume(returning: Git.Result(
            exitCode: proc.terminationStatus,
            stdout: stdout,
            stderr: stderr
          ))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
  
  /// Parse issue number from GitHub issue URL.
  /// Expected format: "https://github.com/owner/repo/issues/123"
  private func parseIssueNumberFromURL(_ url: String) -> Int? {
    let components = url.split(separator: "/")
    guard let lastComponent = components.last,
          let number = Int(lastComponent) else {
      return nil
    }
    return number
  }

  // MARK: - Projects

  // MARK: - Text Dumps

  func loadTextDumps() {
    Task {
      do {
        let dumps = try await api.loadTextDumps()
        await MainActor.run {
          self.textDumps = dumps
        }
      } catch {
        print("⚠️ Failed to load text dumps: \(error)")
        await MainActor.run {
          self.textDumps = []
        }
      }
    }
  }

  /// Mark a completed text dump as reviewed by the user.
  func markDumpReviewed(_ dumpId: String) {
    reviewedDumpIds.insert(dumpId)
  }

  /// Get tasks created from a specific text dump.
  func tasksForDump(_ dump: TextDump) -> [DashboardTask] {
    guard let ids = dump.taskIds else { return [] }
    let idSet = Set(ids)
    return tasks.filter { idSet.contains($0.id) }
  }

  /// Delete a single task by ID (used from text dump results).
  func deleteTask(taskId: String) {
    // Optimistically remove from cache (UI updates instantly)
    cache.removeTask(taskId)
    
    Task {
      do {
        try await api.deleteTask(taskId: taskId)
        cache.invalidateTasks()
      } catch {
        await MainActor.run {
          self.flashError("Failed to delete task: \(error.localizedDescription)")
          // Force reload to restore the task
          self.cache.invalidateTasks()
          Task {
            await self.pollingManager.refreshStaleData()
          }
        }
      }
    }
  }

  /// Update a task's title and notes (used from text dump results).
  func updateTaskTitleAndNotes(taskId: String, title: String, notes: String?) {
    editTask(taskId: taskId, title: title, notes: notes, autoPush: true)
  }

  func submitTextDump(text: String, projectId: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    Task {
      do {
        let _ = try await api.createTextDump(
          content: trimmed,
          source: "dashboard",
          context: "project:\(projectId)"
        )
        await MainActor.run {
          self.flashSuccess("Text dump submitted")
          self.reload()
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save text dump: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Projects

  func createProject(title: String, notes: String?, type: ProjectType = .kanban) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }

    let id = uniqueProjectId(for: trimmedTitle)

    // Local update (optimistic)
    let now = Date()
    let p = Project(
      id: id,
      title: trimmedTitle,
      createdAt: now,
      updatedAt: now,
      notes: (trimmedNotes?.isEmpty == true) ? nil : trimmedNotes,
      archived: false,
      type: type
    )
    projects.append(p)
    selectedProjectId = p.id

    Task {
      do {
        // Create via API
        _ = try await apiService?.createProject(id: id, title: trimmedTitle, type: type, notes: trimmedNotes)
        
        // Save README if notes exist
        if let notes = trimmedNotes, !notes.isEmpty {
          try await api.saveProjectReadme(projectId: id, content: notes)
        }
        
        await MainActor.run {
          self.flashSuccess("Project created")
          self.reload()
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save project: \(error.localizedDescription)")
        }
      }
    }
  }

  func renameProject(id: String, newTitle: String) {
    let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    // Local update (optimistic)
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].title = trimmed
      projects[idx].updatedAt = Date()
    }

    Task {
      do {
        try await api.renameProject(id: id, newTitle: trimmed)
      } catch {
        await MainActor.run {
          self.flashError("Failed to rename project: \(error.localizedDescription)")
        }
      }
    }
  }

  func updateProjectNotes(id: String, notes: String?) {
    let clean = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

    // Local update (optimistic)
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].notes = (clean?.isEmpty == true) ? nil : clean
      projects[idx].updatedAt = Date()
    }

    // Keep README in sync with project notes (they are the same content)
    if id == selectedProjectId {
      projectReadme = clean ?? ""
    }

    Task {
      do {
        try await api.updateProjectNotes(id: id, notes: clean)
        // Sync to README file as well
        try await api.saveProjectReadme(projectId: id, content: clean ?? "")
      } catch {
        await MainActor.run {
          self.flashError("Failed to update project: \(error.localizedDescription)")
        }
      }
    }
  }

  func updateProjectSyncMode(id: String, syncMode: SyncMode, githubConfig: GitHubConfig?) {
    // Local update (optimistic)
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].syncMode = syncMode
      projects[idx].githubConfig = githubConfig
      projects[idx].updatedAt = Date()
    }

    Task {
      do {
        try await api.updateProjectSyncMode(id: id, syncMode: syncMode, githubConfig: githubConfig)
      } catch {
        await MainActor.run {
          self.flashError("Failed to update project sync mode: \(error.localizedDescription)")
        }
      }
    }
  }

  func deleteProject(id: String) {
    guard id != "default" else { return }

    // Cascade delete: remove all tasks belonging to this project
    let taskIdsToDelete = tasks.filter { ($0.projectId ?? "default") == id }.map { $0.id }
    tasks.removeAll { ($0.projectId ?? "default") == id }

    // Remove locally (optimistic)
    projects.removeAll { $0.id == id }

    // Navigate back to home screen
    if selectedProjectId == id {
      selectedProjectId = "default"
      showOverview = true
    }

    Task {
      do {
        // Delete task files
        for taskId in taskIdsToDelete {
          try await api.deleteTask(taskId: taskId)
        }

        // Delete research data
        try await api.deleteResearchData(projectId: id)

        // Delete tracker data
        try await api.deleteTrackerData(projectId: id)

        // Delete the project entry itself
        try await api.deleteProject(id: id)
      } catch {
        await MainActor.run {
          self.flashError("Failed to delete project: \(error.localizedDescription)")
        }
      }
    }
  }

  func archiveProject(id: String) {
    guard id != "default" else { return }

    // Local update (optimistic)
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].archived = true
      projects[idx].updatedAt = Date()
    }
    if selectedProjectId == id {
      selectedProjectId = "default"
    }

    Task {
      do {
        try await api.archiveProject(id: id)
      } catch {
        await MainActor.run {
          self.flashError("Failed to archive project: \(error.localizedDescription)")
        }
      }
    }
  }

  func unarchiveProject(id: String) {
    // Local update (optimistic)
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].archived = false
      projects[idx].updatedAt = Date()
    }

    Task {
      do {
        try await apiService?.unarchiveProject(id: id)
        await silentReload()
      } catch {
        await MainActor.run {
          self.flashError("Failed to unarchive project: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Move a project up or down in the sorted list. `direction` is -1 (up) or +1 (down).
  func moveProject(id: String, direction: Int) {
    guard let repoURL else { return }

    // Work with the sorted active list to determine new order
    var sorted = sortedActiveProjects
    guard let fromIndex = sorted.firstIndex(where: { $0.id == id }) else { return }
    let toIndex = fromIndex + direction
    guard toIndex >= 0, toIndex < sorted.count else { return }

    // Swap
    sorted.swapAt(fromIndex, toIndex)

    // Reassign sortOrder based on new positions
    for (i, project) in sorted.enumerated() {
      if let idx = projects.firstIndex(where: { $0.id == project.id }) {
        projects[idx].sortOrder = i
        projects[idx].updatedAt = Date()
      }
    }

    // Persist via API
    Task {
      do {
        let pfile = try await api.loadProjects()
        var updated = pfile
        for (i, project) in sorted.enumerated() {
          if let idx = updated.projects.firstIndex(where: { $0.id == project.id }) {
            updated.projects[idx].sortOrder = i
            updated.projects[idx].updatedAt = Date()
          }
        }
        updated.generatedAt = Date()
        try await api.saveProjects(updated)
      } catch {
        await MainActor.run {
          self.flashError("Failed to reorder projects: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Reorder a project by moving it before another project (drag-and-drop).
  func reorderProject(fromId: String, beforeId: String) {
    guard fromId != beforeId, let repoURL else { return }

    var sorted = sortedActiveProjects
    guard let fromIndex = sorted.firstIndex(where: { $0.id == fromId }) else { return }
    let moved = sorted.remove(at: fromIndex)
    if let toIndex = sorted.firstIndex(where: { $0.id == beforeId }) {
      sorted.insert(moved, at: toIndex)
    } else {
      sorted.append(moved)
    }

    // Reassign sortOrder
    for (i, project) in sorted.enumerated() {
      if let idx = projects.firstIndex(where: { $0.id == project.id }) {
        projects[idx].sortOrder = i
        projects[idx].updatedAt = Date()
      }
    }

    // Persist via API
    Task {
      do {
        let pfile = try await api.loadProjects()
        var updated = pfile
        for (i, project) in sorted.enumerated() {
          if let idx = updated.projects.firstIndex(where: { $0.id == project.id }) {
            updated.projects[idx].sortOrder = i
            updated.projects[idx].updatedAt = Date()
          }
        }
        updated.generatedAt = Date()
        try await api.saveProjects(updated)
      } catch {
        await MainActor.run {
          self.flashError("Failed to reorder projects: \(error.localizedDescription)")
        }
      }
    }
  }

  private func uniqueProjectId(for title: String) -> String {
    func slugify(_ s: String) -> String {
      let lower = s.lowercased()
      var out = ""
      var prevDash = false
      for ch in lower {
        if ch.isLetter || ch.isNumber {
          out.append(ch)
          prevDash = false
        } else {
          if !prevDash {
            out.append("-")
            prevDash = true
          }
        }
      }
      out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      return out.isEmpty ? "project" : out
    }

    let base = slugify(title)
    if !projects.contains(where: { $0.id == base }) { return base }
    var i = 2
    while projects.contains(where: { $0.id == "\(base)-\(i)" }) { i += 1 }
    return "\(base)-\(i)"
  }

  func reorderTask(taskId: String, to status: TaskStatus, beforeTaskId: String?) {
    guard let repoURL else { return }

    // Get tasks in this column sorted by current order
    var columnTasks = filteredTasks.filter { t in
      // Match the column logic from `columns`
      switch status {
      case .active:
        if t.status == .active || t.status == .waitingOn { return true }
        if case .other = t.status { return true }
        return false
      case .completed: return t.status == .completed
      case .rejected: return t.status == .rejected
      default: return t.status == status
      }
    }

    // Remove the dragged task from column if already there
    columnTasks.removeAll { $0.id == taskId }

    // Insert at position
    if let beforeId = beforeTaskId,
       let idx = columnTasks.firstIndex(where: { $0.id == beforeId }) {
      columnTasks.insert(DashboardTask(id: taskId, title: "", status: status, owner: .lobs, createdAt: Date(), updatedAt: Date()), at: idx)
    } else {
      columnTasks.append(DashboardTask(id: taskId, title: "", status: status, owner: .lobs, createdAt: Date(), updatedAt: Date()))
    }

    // Assign sortOrder
    for (i, t) in columnTasks.enumerated() {
      if let idx = tasks.firstIndex(where: { $0.id == t.id }) {
        tasks[idx].sortOrder = i
        tasks[idx].status = status
      }
    }

    // Persist all affected tasks via API
    Task {
      do {
        for t in columnTasks {
          if let task = tasks.first(where: { $0.id == t.id }) {
            try await api.setStatus(taskId: task.id, status: task.status)
            try await api.setSortOrder(taskId: task.id, sortOrder: task.sortOrder)
          }
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save reorder: \(error.localizedDescription)")
        }
      }
    }
  }

  func moveTask(taskId: String, to status: TaskStatus) {
    optimisticUpdate(taskId: taskId, localMutation: { $0.status = status }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: move \(taskId) to \(status.rawValue)",
        autoPush: true
      )
    }
  }

  // MARK: - Bulk Actions

  /// Bulk-move all multi-selected tasks to a new status.
  func bulkMoveSelected(to status: TaskStatus) {
    guard !multiSelectedTaskIds.isEmpty else { return }
    let ids = multiSelectedTaskIds

    // Apply local mutations immediately to cache
    withAnimation(.easeInOut(duration: 0.25)) {
      for id in ids {
        cache.updateTask(id) { task in
          task.status = status
          if status == .completed {
            task.workState = nil
            if task.finishedAt == nil { task.finishedAt = Date() }
          } else if status == .active {
            task.workState = .notStarted
            if task.startedAt == nil { task.startedAt = Date() }
          }
        }
      }
    }

    // Persist via API
    Task {
      do {
        for id in ids {
          if let task = cache.tasks.first(where: { $0.id == id }) {
            try await api.saveExistingTask(task)
          }
        }
        cache.invalidateTasks()
      } catch {
        await MainActor.run {
          self.flashError("Failed to save bulk move: \(error.localizedDescription)")
        }
      }
    }

    clearMultiSelect()

    // Auto-unblock dependents for completed tasks
    if status == .completed {
      for id in ids {
        autoUnblockDependents(of: id, autoPush: true)
      }
    }
  }

  /// Bulk-approve all multi-selected tasks (inbox → active).
  func bulkApproveSelected() {
    guard let repoURL, !multiSelectedTaskIds.isEmpty else { return }
    let ids = multiSelectedTaskIds

    for id in ids {
      if let idx = tasks.firstIndex(where: { $0.id == id }) {
        withAnimation(.easeInOut(duration: 0.25)) {
          tasks[idx].reviewState = .approved
          tasks[idx].status = .active
          tasks[idx].workState = .notStarted
          tasks[idx].updatedAt = Date()
          if tasks[idx].startedAt == nil { tasks[idx].startedAt = Date() }
        }
      }
    }

    Task {
      do {
        for id in ids {
          if let task = tasks.first(where: { $0.id == id }) {
            try await api.saveExistingTask(task)
          }
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save bulk approve: \(error.localizedDescription)")
        }
      }
    }

    clearMultiSelect()
  }

  /// Bulk-reject all multi-selected tasks.
  func bulkRejectSelected() {
    guard let repoURL, !multiSelectedTaskIds.isEmpty else { return }
    let ids = multiSelectedTaskIds

    for id in ids {
      if let idx = tasks.firstIndex(where: { $0.id == id }) {
        withAnimation(.easeInOut(duration: 0.25)) {
          tasks[idx].reviewState = .rejected
          tasks[idx].status = .rejected
          tasks[idx].updatedAt = Date()
        }
      }
    }

    Task {
      do {
        for id in ids {
          if let task = tasks.first(where: { $0.id == id }) {
            try await api.saveExistingTask(task)
          }
        }
      } catch {
        await MainActor.run {
          self.flashError("Failed to save bulk reject: \(error.localizedDescription)")
        }
      }
    }

    clearMultiSelect()
  }

  /// Toggle the pinned/starred state of a task.
  func togglePinTask(taskId: String, autoPush: Bool) {
    let currentlyPinned = tasks.first(where: { $0.id == taskId })?.pinned ?? false
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.pinned = !currentlyPinned ? true : nil
    }) { _ in }
  }

  func startTimer(taskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.startedAt = Date()
      $0.finishedAt = nil
      $0.updatedAt = Date()
    }) { _ in }
  }

  func stopTimer(taskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.finishedAt = Date()
      $0.updatedAt = Date()
    }) { _ in }
  }

  func resetTimer(taskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.startedAt = nil
      $0.finishedAt = nil
      $0.updatedAt = Date()
    }) { _ in }
  }

  func editTask(taskId: String, title: String, notes: String?, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { $0.title = t }
      let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
      $0.notes = (n?.isEmpty == true) ? nil : n
      $0.updatedAt = Date()
    }) { _ in }
  }

  func setTaskShape(taskId: String, shape: TaskShape?, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.shape = shape
      $0.updatedAt = Date()
    }) { _ in }
  }

  func setTaskAgent(taskId: String, agent: String?, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.agent = agent
      $0.updatedAt = Date()
    }) { _ in }
  }

  // MARK: - Task Dependencies

  func addBlocker(taskId: String, blockerTaskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      var blockers = $0.blockedBy ?? []
      if !blockers.contains(blockerTaskId) {
        blockers.append(blockerTaskId)
      }
      $0.blockedBy = blockers
      $0.workState = .blocked
    }) { _ in }
  }

  func removeBlocker(taskId: String, blockerTaskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      var blockers = $0.blockedBy ?? []
      blockers.removeAll { $0 == blockerTaskId }
      $0.blockedBy = blockers.isEmpty ? nil : blockers
      if blockers.isEmpty && $0.workState == .blocked {
        $0.workState = .notStarted
      }
    }) { _ in }
  }

  // MARK: - Research Tiles

  func addTile(type: ResearchTileType, title: String, url: String? = nil, content: String? = nil, claim: String? = nil) {
    guard let repoURL else { return }
    let now = Date()
    let tile = ResearchTile(
      id: UUID().uuidString,
      projectId: selectedProjectId,
      type: type,
      title: title,
      tags: nil,
      status: .active,
      author: "rafe",
      createdAt: now,
      updatedAt: now,
      url: url,
      summary: nil,
      snapshot: nil,
      content: content,
      claim: claim,
      confidence: nil,
      evidence: nil,
      counterpoints: nil,
      options: nil
    )

    researchTiles.insert(tile, at: 0)

    Task {
      do {
        try await api.saveTile(tile)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save tile: \(error.localizedDescription)")
        }
      }
    }
  }

  func updateTile(_ tile: ResearchTile) {
    guard let repoURL else { return }
    var updated = tile
    updated.updatedAt = Date()

    if let idx = researchTiles.firstIndex(where: { $0.id == tile.id }) {
      researchTiles[idx] = updated
    }

    Task {
      do {
        try await api.saveTile(updated)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save tile: \(error.localizedDescription)")
        }
      }
    }
  }

  func removeTile(_ tile: ResearchTile) {
    guard let repoURL else { return }
    researchTiles.removeAll { $0.id == tile.id }

    Task {
      do {
        try await api.deleteTile(projectId: tile.projectId, tileId: tile.id)
      } catch {
        await MainActor.run {
          self.flashError("Failed to delete tile: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Research Requests

  func addRequest(prompt: String, tileId: String? = nil, priority: ResearchPriority? = nil, deliverables: [RequestDeliverable]? = nil) {
    guard let repoURL else { return }
    let now = Date()
    let req = ResearchRequest(
      id: UUID().uuidString,
      projectId: selectedProjectId,
      tileId: tileId,
      prompt: prompt,
      status: .open,
      response: nil,
      author: "rafe",
      priority: priority,
      deliverables: deliverables,
      createdAt: now,
      updatedAt: now
    )

    researchRequests.insert(req, at: 0)

    Task {
      do {
        try await api.addResearchRequest(projectId: selectedProjectId, request: req)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save request: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Persist a research request update to the control repository and push.
  func updateRequest(_ request: ResearchRequest) {
    guard let repoURL else { return }
    var updated = request
    updated.updatedAt = Date()

    if let idx = researchRequests.firstIndex(where: { $0.id == request.id }) {
      researchRequests[idx] = updated
    }

    Task {
      do {
        try await api.saveRequest(updated)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save request: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Research Request Triage Helpers

  func updateResearchRequestPriority(requestId: String, priority: ResearchPriority?) {
    guard let req = researchRequests.first(where: { $0.id == requestId }) else { return }
    var updated = req
    updated.priority = priority
    updateRequest(updated)
  }

  func updateResearchRequestStatus(requestId: String, status: ResearchRequestStatus) {
    guard let req = researchRequests.first(where: { $0.id == requestId }) else { return }
    var updated = req
    updated.status = status
    updateRequest(updated)
  }

  /// Edit a research request's prompt with versioning. Saves the old prompt in editHistory.
  func editResearchRequestWithVersioning(requestId: String, newPrompt: String, editedBy: String = "rafe") {
    guard let req = researchRequests.first(where: { $0.id == requestId }) else { return }
    var updated = req

    // Save current prompt as a version before overwriting
    let versionNumber = (req.editHistory?.count ?? 0) + 1
    let snapshot = RequestEditVersion(
      id: "v\(versionNumber)",
      prompt: req.prompt,
      editedAt: Date(),
      editedBy: editedBy
    )
    var history = updated.editHistory ?? []
    history.append(snapshot)
    updated.editHistory = history
    updated.prompt = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    updateRequest(updated)
  }

  /// Split a research request into a sub-request. Creates a new request with parentRequestId set.
  func splitResearchRequest(parentId: String, newPrompt: String) {
    guard let parent = researchRequests.first(where: { $0.id == parentId }) else { return }
    guard let repoURL else { return }
    let now = Date()
    let sub = ResearchRequest(
      id: UUID().uuidString,
      projectId: parent.projectId,
      tileId: parent.tileId,
      prompt: newPrompt,
      status: .open,
      response: nil,
      author: "rafe",
      priority: parent.priority,
      deliverables: nil,
      editHistory: nil,
      parentRequestId: parentId,
      assignedWorker: nil,
      createdAt: now,
      updatedAt: now
    )

    researchRequests.insert(sub, at: 0)

    Task {
      do {
        try await api.addResearchRequest(projectId: parent.projectId, request: sub)
      } catch {
        await MainActor.run {
          self.flashError("Failed to save sub-request: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Update deliverables on a research request.
  func updateResearchRequestDeliverables(requestId: String, deliverables: [RequestDeliverable]) {
    guard let req = researchRequests.first(where: { $0.id == requestId }) else { return }
    var updated = req
    updated.deliverables = deliverables.isEmpty ? nil : deliverables
    updateRequest(updated)
  }

  /// Toggle a specific deliverable's fulfilled state.
  func toggleDeliverableFulfilled(requestId: String, deliverableId: String) {
    guard let req = researchRequests.first(where: { $0.id == requestId }) else { return }
    var updated = req
    guard var dels = updated.deliverables,
          let idx = dels.firstIndex(where: { $0.id == deliverableId }) else { return }
    dels[idx].fulfilled.toggle()
    updated.deliverables = dels
    updateRequest(updated)
  }

  // MARK: - Async Git Helpers (Not needed in API mode)
  
  private func asyncCommitAndMaybePush(repoURL: URL, message: String, autoPush: Bool) async throws {
    // No-op in API mode - the server handles all persistence
  }

  func updatePendingChangesCount() {
    guard let repoURL = repoURL else {
      pendingChangesCount = 0
      return
    }

    Task.detached {
      // Count commits ahead of origin/main
      let ahead = await Git.runAsyncWithErrorHandling(["rev-list", "--count", "origin/main..HEAD"], cwd: repoURL)
      let count = ahead.success ? (Int(ahead.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) : 0

      await MainActor.run {
        self.pendingChangesCount = count
      }
    }
  }

  // MARK: - Git State Sync (Not needed in API mode)
  // The API server handles all state persistence, so we don't need git operations for state management
  
  private func syncRepo(repoURL: URL) throws {
    // No-op in API mode - state is managed by the server
  }

  /// Async version of syncRepo — no-op in API mode
  private func syncRepoAsync(repoURL: URL) async throws {
    // No-op in API mode - state is managed by the server
  }

  /// Auto-commit methods - no-op in API mode
  private func autoCommitLocalChanges(repoURL: URL) throws {
    // No-op in API mode
  }

  /// Async version of autoCommitLocalChanges - no-op in API mode
  private func autoCommitLocalChangesAsync(repoURL: URL) async throws {
    // No-op in API mode
  }

  private func commitAndMaybePush(repoURL: URL, message: String, autoPush: Bool) throws {
    // No-op in API mode
  }

  // Drag-and-drop support
  @Published var draggingTaskId: String? = nil

  // MARK: - Filtered Tasks Cache (Performance Optimization)
  
  /// Invalidate the filtered tasks cache when filter dependencies change.
  private func invalidateFilteredTasksCache() {
    _filteredTasksCacheValid = false
  }
  
  /// Recompute the filtered tasks cache.
  private func recomputeFilteredTasks() {
    var out = tasks

    // Project scoping
    out = out.filter { t in
      (t.projectId ?? "default") == selectedProjectId
    }

    // Inbox is a filter, not a column.
    if showInboxOnly {
      out = out.filter { $0.status == .inbox }
    } else {
      out = out.filter { $0.status != .inbox }
    }

    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !q.isEmpty {
      out = out.filter { t in
        let hay = (t.title + "\n" + (t.notes ?? "")).lowercased()
        return hay.contains(q)
      }
    }

    switch ownerFilter {
    case "lobs":
      out = out.filter { if case .lobs = $0.owner { return true } else { return false } }
    case "rafe":
      out = out.filter { if case .rafe = $0.owner { return true } else { return false } }
    case "other":
      out = out.filter { if case .other = $0.owner { return true } else { return false } }
    default:
      break
    }

    // Shape filter
    if let shapeFilter {
      out = out.filter { $0.shape == shapeFilter }
    }

    // Pinned tasks float to top within their column grouping
    out.sort { a, b in
      let ap = a.pinned ?? false
      let bp = b.pinned ?? false
      if ap != bp { return ap }
      return false // preserve existing order for non-pinned
    }

    _cachedFilteredTasks = out
    _filteredTasksCacheValid = true
  }

  var filteredTasks: [DashboardTask] {
    if !_filteredTasksCacheValid {
      recomputeFilteredTasks()
    }
    return _cachedFilteredTasks
  }

  var columns: [AnyTaskColumn] {
    let activeCol = AnyTaskColumn(title: "Active", dropStatus: .active) { t in
      if t.status == .active || t.status == .waitingOn { return true }
      // Unknown statuses default to Active column
      switch t.status {
      case .inbox, .active, .waitingOn, .completed, .rejected:
        return false
      case .other:
        return true
      }
    }

    return [
      activeCol,

      .init(title: "Done", dropStatus: .completed) { t in
        t.status == .completed
      },

      .init(title: "Rejected", dropStatus: .rejected) { $0.status == .rejected },
    ]
  }

  private func loadArtifactForSelected() {
    guard let selectedId = selectedTaskId else {
      artifactText = "(select a task)"
      return
    }
    
    Task {
      do {
        let content = try await api.loadTaskArtifact(taskId: selectedId)
        await MainActor.run {
          artifactText = content.isEmpty ? "(no artifact)" : content
        }
      } catch {
        await MainActor.run {
          artifactText = "(artifact load error: \(error.localizedDescription))"
        }
      }
    }
  }

  // MARK: - Keyboard Navigation

  /// Tasks in the same column as the currently selected task.
  private func tasksInCurrentColumn() -> [DashboardTask] {
    guard let currentId = selectedTaskId,
          let current = filteredTasks.first(where: { $0.id == currentId }) else {
      return filteredTasks
    }
    // Find which column the current task belongs to
    let col = columns.first(where: { $0.matches(current) })
    guard let col else { return filteredTasks }
    return filteredTasks.filter(col.matches)
  }

  func selectNextTask() {
    let visible = tasksInCurrentColumn()
    guard !visible.isEmpty else { return }
    if let current = selectedTaskId, let idx = visible.firstIndex(where: { $0.id == current }) {
      let next = min(idx + 1, visible.count - 1)
      selectTask(visible[next])
    } else {
      // Nothing selected — select first task in first non-empty column
      let allVisible = filteredTasks
      if let first = allVisible.first { selectTask(first) }
    }
  }

  func selectPreviousTask() {
    let visible = tasksInCurrentColumn()
    guard !visible.isEmpty else { return }
    if let current = selectedTaskId, let idx = visible.firstIndex(where: { $0.id == current }) {
      let prev = max(idx - 1, 0)
      selectTask(visible[prev])
    } else {
      let allVisible = filteredTasks
      if let last = allVisible.last { selectTask(last) }
    }
  }

  /// Move selection to the next column (right arrow).
  func selectNextColumn() {
    guard let currentId = selectedTaskId,
          let current = filteredTasks.first(where: { $0.id == currentId }) else {
      // Nothing selected — select first task
      if let first = filteredTasks.first { selectTask(first) }
      return
    }
    let currentColIdx = columns.firstIndex(where: { $0.matches(current) }) ?? 0
    // Find next non-empty column
    for offset in 1...columns.count {
      let nextIdx = (currentColIdx + offset) % columns.count
      let colTasks = filteredTasks.filter(columns[nextIdx].matches)
      if let first = colTasks.first {
        selectTask(first)
        return
      }
    }
  }

  /// Move selection to the previous column (left arrow).
  func selectPreviousColumn() {
    guard let currentId = selectedTaskId,
          let current = filteredTasks.first(where: { $0.id == currentId }) else {
      if let first = filteredTasks.first { selectTask(first) }
      return
    }
    let currentColIdx = columns.firstIndex(where: { $0.matches(current) }) ?? 0
    // Find previous non-empty column
    for offset in 1...columns.count {
      let prevIdx = (currentColIdx - offset + columns.count) % columns.count
      let colTasks = filteredTasks.filter(columns[prevIdx].matches)
      if let first = colTasks.first {
        selectTask(first)
        return
      }
    }
  }

  // App icon is bundled in Resources/AppIcon.png (no user customization).

  // MARK: - Async Data Loading Helpers

  /// Load research data asynchronously (off main thread)
  private func loadResearchDataAsync() async {
    guard await MainActor.run(body: { isResearchProject }) else { return }
    let projectId = await MainActor.run(body: { selectedProjectId })
    
    do {
      let doc = try await api.loadResearchDoc(projectId: projectId)
      let sources = try await api.loadResearchSources(projectId: projectId)
      let requests = try await api.loadResearchRequests(projectId: projectId)
      
      await MainActor.run {
        self.researchDocContent = doc ?? ""
        self.researchSources = sources
        self.researchRequests = requests
        // Tiles and deliverables are computed from the doc content
        self.researchTiles = []
        self.researchDeliverables = []
      }
    } catch {
      print("⚠️ Failed to load research data: \(error)")
      await MainActor.run {
        self.researchDocContent = ""
        self.researchSources = []
        self.researchRequests = []
        self.researchTiles = []
        self.researchDeliverables = []
      }
    }
  }

  /// Load tracker data asynchronously (off main thread)
  private func loadTrackerDataAsync() async {
    guard await MainActor.run(body: { isTrackerProject }) else { return }
    let projectId = await MainActor.run(body: { selectedProjectId })
    
    do {
      let items = try await api.loadTrackerItems(projectId: projectId)
      
      await MainActor.run {
        self.trackerItems = items
        // Requests are tracked separately if needed
        self.trackerRequests = []
      }
    } catch {
      print("⚠️ Failed to load tracker data: \(error)")
      await MainActor.run {
        self.trackerItems = []
        self.trackerRequests = []
      }
    }
  }

  /// Load inbox items asynchronously (off main thread)
  private func loadInboxItemsAsync() async {
    do {
      let items = try await api.loadInboxItems()
      
      await MainActor.run {
        // Apply read state to items
        var itemsWithReadState = items
        for i in itemsWithReadState.indices {
          itemsWithReadState[i].isRead = self.readItemIds.contains(itemsWithReadState[i].id)
        }
        self.inboxItems = itemsWithReadState
      }
    } catch {
      print("⚠️ Failed to load inbox items: \(error)")
    }
  }

  /// Load worker status asynchronously (off main thread)
  private func loadWorkerStatusAsync() async {
    do {
      let status = try await api.loadWorkerStatus()
      let history = try await api.loadWorkerHistory()
      
      await MainActor.run {
        self.workerStatus = status
        self.workerHistory = history
        self.mainSessionUsage = nil
      }
    } catch {
      print("⚠️ Failed to load worker status: \(error)")
    }
  }

  /// Load per-agent statuses via API
  private func loadAgentStatusesAsync() async {
    do {
      let statuses = try await api.loadAgentStatuses()
      await MainActor.run {
        self.agentStatuses = statuses
      }
    } catch {
      print("⚠️ Failed to load agent statuses: \(error)")
    }
  }

  /// Load agent documents (reports & research) asynchronously
  private func loadAgentDocumentsAsync() async {
    do {
      var docs = try await api.loadAgentDocuments()
      
      // Capture read state
      let readIds = await readDocumentIds
      
      // Apply read state
      for i in docs.indices {
        docs[i].isRead = readIds.contains(docs[i].id)
      }
      
      await MainActor.run {
        self.agentDocuments = docs
      }
    } catch {
      print("⚠️ Failed to load agent documents: \(error)")
    }
  }

  /// Check for dashboard updates asynchronously
  private func checkForDashboardUpdateAsync() async {
    guard let dashURL = dashboardRepoURL else { return }
    
    // Throttle checks (don't check more than once per 5 minutes)
    if let last = lastDashboardUpdateCheckAt,
       Date().timeIntervalSince(last) < 300 {
      return
    }
    
    let built = builtFromCommit
    
    let result: (String, String, Int, Bool, [String])? = await Task.detached {
      // Fetch latest from origin
      let fetch = Git.runWithErrorHandling(["fetch", "origin", "main"], cwd: dashURL)
      guard fetch.success else { return nil }

      let localCommit = Git.runWithErrorHandling(["rev-parse", "--short", "HEAD"], cwd: dashURL)
      let remoteCommit = Git.runWithErrorHandling(["rev-parse", "--short", "origin/main"], cwd: dashURL)
      let behindRes = Git.runWithErrorHandling(
        ["rev-list", "--count", "HEAD..origin/main"],
        cwd: dashURL
      )

      let local = localCommit.output.trimmingCharacters(in: .whitespacesAndNewlines)
      let remote = remoteCommit.output.trimmingCharacters(in: .whitespacesAndNewlines)
      let behindRemote = Int(behindRes.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

      // Check if local HEAD is ahead of the build commit (pulled but not compiled)
      var needsRebuild = false
      var aheadOfBuild = 0
      if !built.isEmpty {
        let aheadResult = Git.runWithErrorHandling(
          ["rev-list", "--count", "\(built)..HEAD"], cwd: dashURL
        )
        aheadOfBuild = Int(aheadResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        needsRebuild = aheadOfBuild > 0
      }

      let totalBehind = behindRemote + aheadOfBuild

      // Fetch commit summaries for pending updates
      var commits: [String] = []
      if needsRebuild, !built.isEmpty {
        let logResult = Git.runWithErrorHandling(
          ["log", "--oneline", "\(built)..HEAD"], cwd: dashURL
        )
        if logResult.success {
          commits += logResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").map(String.init)
        }
      }
      if behindRemote > 0 {
        let logResult = Git.runWithErrorHandling(
          ["log", "--oneline", "HEAD..origin/main"], cwd: dashURL
        )
        if logResult.success {
          commits += logResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").map(String.init)
        }
      }

      return (local, remote, totalBehind, needsRebuild && behindRemote == 0, commits)
    }.value
    
    await MainActor.run {
      self.lastDashboardUpdateCheckAt = Date()
      
      guard let (local, remote, totalBehind, needsRebuild, commits) = result else { return }
      
      self.dashboardLocalCommit = local
      self.dashboardRemoteCommit = remote
      self.dashboardCommitsBehind = totalBehind
      self.dashboardUpdateAvailable = totalBehind > 0
      self.dashboardNeedsRebuild = needsRebuild
      self.dashboardUpdateCommits = commits
    }
  }

  /// Check control repo status asynchronously
  private func checkControlRepoStatusAsync(force: Bool = false) async {
    guard let repoURL else { return }
    
    // Throttle: don't check more than once every 10 seconds (unless forced)
    if !force,
       let last = await MainActor.run(body: { lastControlRepoStatusCheck }),
       Date().timeIntervalSince(last) < 10 {
      return
    }
    
    let result = await Task.detached {
      let aheadRes = Git.runWithErrorHandling(
        ["rev-list", "--count", "origin/main..HEAD"],
        cwd: repoURL
      )
      let behindRes = Git.runWithErrorHandling(
        ["rev-list", "--count", "HEAD..origin/main"],
        cwd: repoURL
      )

      let ahead = Int(aheadRes.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
      let behind = Int(behindRes.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

      return (ahead, behind)
    }.value

    let (ahead, behind) = result
    
    await MainActor.run {
      self.controlRepoAhead = ahead
      self.controlRepoBehind = behind
      self.lastControlRepoStatusCheck = Date()
    }
  }

  /// Update pending changes count asynchronously
  private func updatePendingChangesCountAsync(force: Bool = false) async {
    guard let repoURL else { return }
    
    // Throttle: don't check more than once every 5 seconds (unless forced)
    if !force,
       let last = await MainActor.run(body: { lastPendingChangesUpdate }),
       Date().timeIntervalSince(last) < 5 {
      return
    }
    
    let count = await Task.detached {
      // Count commits ahead of origin/main (unpublished changes)
      let ahead = Git.runWithErrorHandling(["rev-list", "--count", "origin/main..HEAD"], cwd: repoURL)
      guard ahead.success else { return 0 }
      return Int(ahead.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }.value
    
    await MainActor.run {
      self.pendingChangesCount = count
      self.lastPendingChangesUpdate = Date()
    }
  }
}
