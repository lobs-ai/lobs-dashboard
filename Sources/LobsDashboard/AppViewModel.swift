import AppKit
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppViewModel: ObservableObject {
  @Published private(set) var repoPath: String = ""
  
  /// Current application configuration (includes user settings)
  @Published var config: AppConfig?
  
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

  /// Whether onboarding is needed (config not set or incomplete)
  var needsOnboarding: Bool {
    guard let config = config else { return true }
    return !config.onboardingComplete || config.controlRepoPath.isEmpty
  }

  @Published var tasks: [DashboardTask] = []
  @Published var selectedTaskId: String? = nil

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
  @Published var readItemIds: Set<String> = [] {
    didSet {
      var s = settings
      s.readInboxItemIds = Array(readItemIds)
      settings = s
    }
  }
  /// Tracks last-seen thread message count per doc ID. When a thread has more messages
  /// than this count, the item shows as having unread follow-ups.
  @Published var lastSeenThreadCounts: [String: Int] = [:] {
    didSet {
      var s = settings
      s.lastSeenThreadCounts = lastSeenThreadCounts
      settings = s
    }
  }
  @Published var showInbox: Bool = false
  @Published var inboxResponsesByDocId: [String: InboxResponse] = [:]
  @Published var inboxThreadsByDocId: [String: InboxThread] = [:]

  /// Threads with local edits that haven't been confirmed pushed yet.
  /// Prevents auto-refresh from overwriting freshly-posted messages.
  private var pendingThreadWrites: [String: InboxThread] = [:]

  // Project README
  @Published var projectReadme: String = ""

  // Worker Status
  @Published var workerStatus: WorkerStatus? = nil
  @Published var workerHistory: WorkerHistory? = nil

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

  @Published var selectedProjectId: String = "default" {
    didSet {
      var s = settings
      s.selectedProjectId = selectedProjectId
      settings = s
      loadResearchData()
      loadTrackerData()
      loadProjectReadme()
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

  /// Whether sync is blocked because the local repo has uncommitted changes.
  @Published var syncBlockedByUncommitted: Bool = false

  /// Number of pending local changes not yet pushed.
  @Published var pendingChangesCount: Int = 0

  // Git push visibility
  /// Timestamp of the last successful push to origin (best-effort; set when dashboard pushes).
  @Published var lastSuccessfulPushAt: Date? = nil
  /// Timestamp of the last push attempt (best-effort).
  @Published var lastPushAttemptAt: Date? = nil
  /// Last push error message (if any). When set, UI should treat remote-derived state as potentially stale.
  @Published var lastPushError: String? = nil

  // Notifications
  @Published var notifications: [DashboardNotification] = []
  @Published var notificationPreferences: NotificationPreferences = .default
  private var batchedNotifications: [DashboardNotification] = []
  private var batchTimer: Timer? = nil
  /// Commit hash of last successful push.
  @Published var lastPushedCommitHash: String? = nil

  // Control repo sync status
  /// How many commits local HEAD is ahead of origin/main (unpublished changes).
  @Published var controlRepoAhead: Int = 0
  /// How many commits origin/main is ahead of local HEAD (need to pull).
  @Published var controlRepoBehind: Int = 0

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
  @Published var searchText: String = ""
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
  @Published var showInboxOnly: Bool = false
  @Published var ownerFilter: String = "all" {
    didSet {
      var s = settings
      s.ownerFilter = ownerFilter
      settings = s
    }
  }

  /// Filter tasks by shape/type. nil = show all.
  @Published var shapeFilter: TaskShape? = nil
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
    config = ConfigManager.load()
    
    // Load repo path from config
    if let loadedConfig = config {
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
      reviewedDumpIds = Set(s.reviewedTextDumpIds)
      appearanceMode = s.appearanceMode
      quickCaptureHotkeyMode = s.quickCaptureHotkeyMode
    } else {
      // No config yet (fresh install or migration failed)
      repoPath = ""
      // Properties will use their default values from UserSettings()
    }
    
    applyAppearance()
    startAutoRefreshIfNeeded()

    // Check for dashboard source updates on launch
    checkForDashboardUpdate()
    refreshWorkerRequestPending()

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
        isGitBusy = false
        return
      }

      // Back on main actor — load local data (fast file I/O)
      do {
        let store = LobsControlStore(repoRoot: repoURL)

        // Projects
        let pfile = try store.loadProjects()
        if pfile.projects.map({ $0.id }) != projects.map({ $0.id }) {
          projects = pfile.projects
        }
        if !projects.contains(where: { $0.id == "default" }) {
          let now = Date()
          projects.insert(Project(id: "default", title: "Default", createdAt: now, updatedAt: now, notes: nil, archived: false), at: 0)
        }
        if !projects.contains(where: { $0.id == selectedProjectId }) {
          selectedProjectId = "default"
        }

        if autoArchiveCompleted {
          try store.archiveCompleted(olderThanDays: archiveCompletedAfterDays)
        }

        if autoArchiveReadInbox {
          try store.archiveReadInboxItems(olderThanDays: archiveReadInboxAfterDays, readItemIds: readItemIds)
        }

        // Track GitHub sync status if selected project uses GitHub mode
        let hasGitHubProject = projects.contains { $0.syncMode == .github && $0.githubConfig?.accessToken != nil }
        if hasGitHubProject {
          isGitHubSyncing = true
        }

        let file = try await store.loadTasks()

        // Update GitHub sync status
        if hasGitHubProject {
          lastGitHubSyncAt = Date()
          lastGitHubSyncError = nil
          isGitHubSyncing = false
        }

        // Only update if something changed (avoid UI flicker).
        if file.tasks.map({ $0.id }).sorted() != tasks.map({ $0.id }).sorted()
          || file.tasks.map({ $0.updatedAt }) != tasks.map({ $0.updatedAt })
          || file.tasks.map({ $0.status.rawValue }) != tasks.map({ $0.status.rawValue }) {
          tasks = file.tasks
          try loadArtifactForSelected(store: store)
        }

        // Refresh research data too
        loadResearchData(store: store)
        loadTrackerData(store: store)
        loadInboxItems(store: store)
        loadWorkerStatus(store: store)

        // Check for dashboard source updates on every sync
        checkForDashboardUpdate()

        // Update pending changes count
        updatePendingChangesCount()
      } catch {
        // Silent — don't overwrite errors from user actions.
        // But do capture GitHub sync errors if applicable
        let hasGitHubProject = projects.contains { $0.syncMode == .github && $0.githubConfig?.accessToken != nil }
        if hasGitHubProject {
          lastGitHubSyncError = error.localizedDescription
          isGitHubSyncing = false
        }
      }
      isGitBusy = false
    }
  }

  var repoURL: URL? {
    guard !repoPath.isEmpty else { return nil }
    return URL(fileURLWithPath: repoPath)
  }

  func setRepoURL(_ url: URL) {
    repoPath = url.path
    
    // Save to ConfigManager
    var updatedConfig = config ?? AppConfig()
    updatedConfig.controlRepoPath = url.path
    updatedConfig.onboardingComplete = true
    config = updatedConfig
    
    do {
      try ConfigManager.save(updatedConfig)
    } catch {
      print("⚠️ Failed to save config: \(error)")
    }
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
  /// Reads from ~/.lobs/dashboard-build-commit (written by bin/build at build time),
  /// falling back to the compile-time BuildInfo.builtCommit.
  private var builtFromCommit: String {
    // Prefer the runtime hash file written by bin/build — this survives pulls
    // without recompilation and always reflects the actual last build.
    let hashFile = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".lobs/dashboard-build-commit")
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

    isGitBusy = true
    Task {
      do {
        // Run git sync off the main thread to avoid UI lag
        try await syncRepoAsync(repoURL: repoURL)
      } catch {
        lastError = String(describing: error)
        isGitBusy = false
        return
      }

      // Back on main actor — load local data (fast file I/O)
      do {
        let store = LobsControlStore(repoRoot: repoURL)

        // Projects
        let pfile = try store.loadProjects()
        projects = pfile.projects
        if !projects.contains(where: { $0.id == "default" }) {
          let now = Date()
          projects.insert(Project(id: "default", title: "Default", createdAt: now, updatedAt: now, notes: nil, archived: false), at: 0)
        }
        if !projects.contains(where: { $0.id == selectedProjectId }) {
          selectedProjectId = "default"
        }

        if autoArchiveCompleted {
          try store.archiveCompleted(olderThanDays: archiveCompletedAfterDays)
        }

        if autoArchiveReadInbox {
          try store.archiveReadInboxItems(olderThanDays: archiveReadInboxAfterDays, readItemIds: readItemIds)
        }

        // Track GitHub sync status if any project uses GitHub mode
        let hasGitHubProject = projects.contains { $0.syncMode == .github && $0.githubConfig?.accessToken != nil }
        if hasGitHubProject {
          isGitHubSyncing = true
        }

        let file = try await store.loadTasks()

        // Update GitHub sync status
        if hasGitHubProject {
          lastGitHubSyncAt = Date()
          lastGitHubSyncError = nil
          isGitHubSyncing = false
        }

        tasks = file.tasks
        lastError = nil
        try loadArtifactForSelected(store: store)

        // Load research data if applicable
        loadResearchData(store: store)
        loadTrackerData(store: store)
        loadInboxItems(store: store)
        loadProjectReadme(store: store)
        loadTemplates()
        loadWorkerStatus(store: store)
        loadTextDumps(store: store)
        refreshWorkerRequestPending()

        refreshProjectLastCommitAt()

        // Manual refresh should also refresh the dashboard update indicator immediately.
        checkForDashboardUpdate(force: true)
        checkControlRepoStatus()

      } catch {
        lastError = String(describing: error)
        // Capture GitHub sync errors if applicable
        let hasGitHubProject = projects.contains { $0.syncMode == .github && $0.githubConfig?.accessToken != nil }
        if hasGitHubProject {
          lastGitHubSyncError = error.localizedDescription
          isGitHubSyncing = false
        }
      }
      isGitBusy = false
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

      // Attempt push
      let push = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
      if !push.success {
        // If push failed, check if we should pull first
        if push.suggestsPull {
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

          // Retry push after successful pull
          let retry = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
          if !retry.success {
            await MainActor.run {
              let errorMsg = retry.error?.errorDescription ?? "Push failed"
              self.lastPushError = errorMsg
              self.flashError(self.lastPushError ?? "Push failed")
              self.isGitBusy = false
            }
            return
          }
        } else {
          // Push failed for a non-recoverable reason
          await MainActor.run {
            let errorMsg = push.error?.errorDescription ?? "Push failed"
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

  func loadResearchData(store: LobsControlStore? = nil) {
    guard let repoURL else { return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    guard isResearchProject else {
      researchTiles = []
      researchRequests = []
      researchDocContent = ""
      researchSources = []
      researchDeliverables = []
      return
    }
    do {
      // Try migrating tiles to doc if needed
      try s.migrateResearchTilesToDoc(projectId: selectedProjectId)

      // Load doc-based content
      researchDocContent = try s.loadResearchDoc(projectId: selectedProjectId)
      researchSources = try s.loadResearchSources(projectId: selectedProjectId)
      researchDeliverables = try s.loadResearchDeliverables(projectId: selectedProjectId)

      // Still load legacy tiles (for backwards compat during transition)
      researchTiles = try s.loadTiles(projectId: selectedProjectId)
      researchRequests = try s.loadRequests(projectId: selectedProjectId)
    } catch {
      flashError("Failed to load research data: \(error.localizedDescription)")
    }
  }

  // MARK: - Research Document Actions

  func saveResearchDocContent(_ content: String) {
    guard let repoURL else { return }
    researchDocContent = content

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveResearchDoc(projectId: selectedProjectId, content: content)
    } catch {
      flashError("Failed to save research doc: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update research doc for \(selectedProjectId)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func saveResearchDeliverableContent(filename: String, content: String) {
    guard let repoURL else { return }

    // Update local cache
    if let idx = researchDeliverables.firstIndex(where: { $0.filename == filename }) {
      researchDeliverables[idx].content = content
      researchDeliverables[idx].modifiedAt = Date()
    }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveResearchDeliverable(projectId: selectedProjectId, filename: filename, content: content)
      // Reload deliverables so modifiedAt reflects the filesystem timestamp ordering
      researchDeliverables = try store.loadResearchDeliverables(projectId: selectedProjectId)
    } catch {
      flashError("Failed to save research deliverable: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update research deliverable \(filename)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func addResearchSource(url: String, title: String, tags: [String]? = nil) {
    guard let repoURL else { return }
    let source = ResearchSource(
      id: UUID().uuidString,
      url: url,
      title: title,
      tags: tags,
      addedAt: Date()
    )
    researchSources.append(source)

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveResearchSources(projectId: selectedProjectId, sources: researchSources)
    } catch {
      flashError("Failed to save source: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: add research source for \(selectedProjectId)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func removeResearchSource(id: String) {
    guard let repoURL else { return }
    researchSources.removeAll { $0.id == id }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveResearchSources(projectId: selectedProjectId, sources: researchSources)
    } catch {
      flashError("Failed to save sources: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: remove research source for \(selectedProjectId)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  // MARK: - Tracker

  func loadTrackerData(store: LobsControlStore? = nil) {
    guard let repoURL else { return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    guard isTrackerProject else {
      trackerItems = []
      trackerRequests = []
      return
    }
    do {
      trackerItems = try s.loadTrackerItems(projectId: selectedProjectId)
      trackerRequests = try s.loadTrackerRequests(projectId: selectedProjectId)
    } catch {
      flashError("Failed to load tracker data: \(error.localizedDescription)")
    }
  }

  func addTrackerItem(title: String, difficulty: String? = nil, tags: [String]? = nil, notes: String? = nil, links: [String]? = nil) {
    guard let repoURL else { return }
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveTrackerItem(item)
    } catch {
      flashError("Failed to save tracker item: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: add tracker item \(item.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func updateTrackerItem(_ item: TrackerItem) {
    guard let repoURL else { return }
    var updated = item
    updated.updatedAt = Date()

    if let idx = trackerItems.firstIndex(where: { $0.id == item.id }) {
      trackerItems[idx] = updated
    }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveTrackerItem(updated)
    } catch {
      flashError("Failed to save tracker item: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update tracker item \(item.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func removeTrackerItem(_ item: TrackerItem) {
    guard let repoURL else { return }
    trackerItems.removeAll { $0.id == item.id }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.deleteTrackerItem(projectId: item.projectId, itemId: item.id)
    } catch {
      flashError("Failed to delete tracker item: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: delete tracker item \(item.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  // MARK: - Tracker Requests (Ask Lobs)

  func addTrackerRequest(prompt: String) {
    guard let repoURL else { return }
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveTrackerRequest(req)
    } catch {
      flashError("Failed to save tracker request: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: add tracker request \(req.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  // MARK: - Inbox

  func loadInboxItems(store: LobsControlStore? = nil) {
    guard let repoURL else { return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    do {
      var items = try s.loadInboxItems()
      // Apply read state
      for i in items.indices {
        items[i].isRead = readItemIds.contains(items[i].id)
      }
      inboxItems = items

      let responses = try s.loadInboxResponses()
      inboxResponsesByDocId = Dictionary(uniqueKeysWithValues: responses.map { ($0.docId, $0) })

      var loadedThreads = try s.loadAllInboxThreads()

      // Merge back any threads with pending local writes that haven't been
      // confirmed pushed yet. This prevents auto-refresh from overwriting
      // freshly-posted messages with stale data from disk/git.
      for (docId, pendingThread) in pendingThreadWrites {
        if let diskThread = loadedThreads[docId] {
          // Keep the pending version if it's newer (more messages or newer timestamp)
          if pendingThread.updatedAt >= diskThread.updatedAt {
            loadedThreads[docId] = pendingThread
          } else {
            // Disk version is newer (remote pushed an update) — drop pending
            pendingThreadWrites.removeValue(forKey: docId)
          }
        } else {
          // Thread only exists locally (new thread not yet on remote)
          loadedThreads[docId] = pendingThread
        }
      }

      inboxThreadsByDocId = loadedThreads
    } catch {
      flashError("Failed to load inbox: \(error.localizedDescription)")
    }
  }

  /// Returns how many follow-up thread messages are currently unread for a doc.
  /// A follow-up is considered unread when the thread has more messages than the
  /// last-seen count recorded locally.
  func unreadFollowupCount(docId: String) -> Int {
    guard let thread = inboxThreadsByDocId[docId] else { return 0 }
    let seen = lastSeenThreadCounts[docId, default: 0]
    return max(0, thread.messages.count - seen)
  }

  func markInboxItemRead(_ item: InboxItem) {
    readItemIds.insert(item.id)
    if let idx = inboxItems.firstIndex(where: { $0.id == item.id }) {
      inboxItems[idx].isRead = true
    }
    // Mark thread follow-ups as seen when opening/marking as read.
    if let thread = inboxThreadsByDocId[item.id] {
      lastSeenThreadCounts[item.id] = thread.messages.count
    }
  }

  func markInboxItemUnread(_ item: InboxItem) {
    readItemIds.remove(item.id)
    if let idx = inboxItems.firstIndex(where: { $0.id == item.id }) {
      inboxItems[idx].isRead = false
    }
    // Do not change lastSeenThreadCounts here.
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
  var unreadInboxCount: Int {
    inboxItems.filter { item in
      !item.isRead || unreadFollowupCount(docId: item.id) > 0
    }.count
  }

  func inboxResponseText(docId: String) -> String {
    inboxResponsesByDocId[docId]?.response ?? ""
  }

  func saveInboxResponse(docId: String, response: String) {
    guard let repoURL else { return }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      let saved = try store.saveInboxResponse(docId: docId, response: response)
      inboxResponsesByDocId[docId] = saved
    } catch {
      flashError("Failed to save inbox response: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: respond to inbox \(docId)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  // MARK: - Project README

  func loadProjectReadme(store: LobsControlStore? = nil) {
    guard let repoURL else { projectReadme = ""; return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    do {
      let readmeContent = try s.loadProjectReadme(projectId: selectedProjectId) ?? ""
      let projectNotes = projects.first(where: { $0.id == selectedProjectId })?.notes ?? ""

      // Reconcile: README and project notes should always be the same.
      // If one is populated and the other isn't, sync the populated one to both.
      if readmeContent.isEmpty && !projectNotes.isEmpty {
        // Notes exist but README doesn't — create README from notes
        projectReadme = projectNotes
        try s.saveProjectReadme(projectId: selectedProjectId, content: projectNotes)
      } else if !readmeContent.isEmpty && projectNotes.isEmpty {
        // README exists but notes are empty — update notes from README
        projectReadme = readmeContent
        if let idx = projects.firstIndex(where: { $0.id == selectedProjectId }) {
          projects[idx].notes = readmeContent
          projects[idx].updatedAt = Date()
        }
        try s.updateProjectNotes(id: selectedProjectId, notes: readmeContent)
      } else {
        // Both populated (or both empty) — README is the source of truth since
        // it supports richer content (multi-line markdown).
        projectReadme = readmeContent
        if !readmeContent.isEmpty && readmeContent != projectNotes {
          if let idx = projects.firstIndex(where: { $0.id == selectedProjectId }) {
            projects[idx].notes = readmeContent
            projects[idx].updatedAt = Date()
          }
          try s.updateProjectNotes(id: selectedProjectId, notes: readmeContent)
        }
      }
    } catch {
      projectReadme = ""
    }
  }

  func saveProjectReadme(content: String) {
    guard let repoURL else { return }
    projectReadme = content

    // Keep project notes in sync with README (they are the same content)
    let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if let idx = projects.firstIndex(where: { $0.id == selectedProjectId }) {
      projects[idx].notes = clean.isEmpty ? nil : clean
      projects[idx].updatedAt = Date()
    }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveProjectReadme(projectId: selectedProjectId, content: content)
      try store.updateProjectNotes(id: selectedProjectId, notes: clean.isEmpty ? nil : clean)
    } catch {
      flashError("Failed to save README: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update project \(selectedProjectId) README",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  // MARK: - Task Templates

  // MARK: - Worker Status

  func loadWorkerStatus(store: LobsControlStore? = nil) {
    guard let repoURL else { workerStatus = nil; workerHistory = nil; return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    let oldStatus = workerStatus
    do {
      workerStatus = try s.loadWorkerStatus()
    } catch {
      workerStatus = nil
    }
    do {
      workerHistory = try s.loadWorkerHistory()
    } catch {
      // Keep last known history on transient decode/read errors.
    }
    do {
      mainSessionUsage = try s.loadMainSessionUsage()
    } catch {
      // Keep last known usage on transient decode/read errors.
    }

    // Detect worker state changes and send macOS notifications
    if let old = oldStatus, let new = workerStatus {
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
  }

  /// Whether a worker request is already pending (file exists on disk).
  @Published var workerRequestPending: Bool = false

  /// Sync `workerRequestPending` with the actual file on disk.
  func refreshWorkerRequestPending() {
    guard let repoURL else { workerRequestPending = false; return }
    workerRequestPending = LobsControlStore(repoRoot: repoURL).workerRequestExists
  }

  /// Request a worker run by writing state/worker-request.json, committing, and pushing.
  func requestWorker() {
    guard let repoURL else { return }
    let store = LobsControlStore(repoRoot: repoURL)
    do {
      try store.writeWorkerRequest()
      // Update immediately so the UI reflects the change without waiting for reload
      workerRequestPending = true
      try commitAndMaybePush(repoURL: repoURL, message: "Request worker from dashboard", autoPush: true)
    } catch {
      print("Failed to request worker: \(error)")
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
    guard let repoURL else { templates = []; return }
    let store = LobsControlStore(repoRoot: repoURL)
    do {
      templates = try store.loadTemplates()
    } catch {
      templates = []
    }
  }

  func saveTemplate(_ template: TaskTemplate) {
    guard let repoURL else { return }

    if let idx = templates.firstIndex(where: { $0.id == template.id }) {
      templates[idx] = template
    } else {
      templates.append(template)
    }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveTemplate(template)
    } catch {
      flashError("Failed to save template: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: save template \(template.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func deleteTemplate(id: String) {
    guard let repoURL else { return }
    templates.removeAll { $0.id == id }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.deleteTemplate(id: id)
    } catch {
      flashError("Failed to delete template: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: delete template \(id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func stampTemplate(_ template: TaskTemplate, autoPush: Bool) {
    guard let repoURL else { return }
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      for task in newTasks {
        _ = try store.addTask(
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
    } catch {
      flashError("Failed to create tasks from template: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        // Check if project uses GitHub sync mode
        let store = LobsControlStore(repoRoot: repoURL)
        if let project = projects.first(where: { $0.id == selectedProjectId }),
           project.syncMode == .github,
           let token = project.githubConfig?.accessToken, !token.isEmpty {
          // Create GitHub issues for all tasks
          for i in 0..<newTasks.count {
            do {
              let updatedTask = try await store.saveTaskToGitHub(task: newTasks[i], project: project, token: token)
              newTasks[i] = updatedTask

              // Update local task with GitHub issue number
              try store.saveExistingTask(updatedTask)

              // Update UI with GitHub issue number
              await MainActor.run {
                if let idx = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
                  tasks[idx] = updatedTask
                }
              }
            } catch {
              print("Warning: Failed to create GitHub issue for task \(newTasks[i].id): \(error)")
            }
          }
        }

        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: stamp template \(template.name) (\(newTasks.count) tasks)",
          autoPush: autoPush
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func postInboxThreadMessage(docId: String, author: String, text: String) {
    guard let repoURL else { return }
    let now = Date()
    let msg = InboxThreadMessage(
      id: UUID().uuidString,
      author: author,
      text: text,
      createdAt: now
    )

    // Update in-memory thread
    if var thread = inboxThreadsByDocId[docId] {
      thread.messages.append(msg)
      thread.updatedAt = now
      inboxThreadsByDocId[docId] = thread

      do {
        let store = LobsControlStore(repoRoot: repoURL)
        try store.saveInboxThread(thread)
      } catch {
        flashError("Failed to save thread: \(error.localizedDescription)")
        return
      }
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

      do {
        let store = LobsControlStore(repoRoot: repoURL)
        try store.saveInboxThread(thread)
      } catch {
        flashError("Failed to save thread: \(error.localizedDescription)")
        return
      }
    }

    // If the user just posted (e.g. author=="rafe"), consider the thread fully read.
    if author.lowercased() == "rafe", let thread = inboxThreadsByDocId[docId] {
      lastSeenThreadCounts[docId] = thread.messages.count
    }

    // Track as pending so auto-refresh won't overwrite it with stale data
    if let thread = inboxThreadsByDocId[docId] {
      pendingThreadWrites[docId] = thread
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: thread reply on \(docId)",
          autoPush: true
        )
        // Push succeeded — safe to clear pending state
        pendingThreadWrites.removeValue(forKey: docId)
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        // Keep pending so the message isn't lost on next refresh
      }
      isGitBusy = false
    }
  }

  func editInboxThreadMessage(docId: String, messageId: String, newText: String) {
    guard let repoURL else { return }
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveInboxThread(thread)
    } catch {
      flashError("Failed to save thread: \(error.localizedDescription)")
      return
    }

    // Track as pending so auto-refresh won't overwrite it with stale data
    pendingThreadWrites[docId] = thread

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: edit thread message on \(docId)",
          autoPush: true
        )
        pendingThreadWrites.removeValue(forKey: docId)
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func deleteInboxThreadMessage(docId: String, messageId: String) {
    guard let repoURL else { return }
    guard var thread = inboxThreadsByDocId[docId],
          let idx = thread.messages.firstIndex(where: { $0.id == messageId }) else { return }

    thread.messages.remove(at: idx)
    thread.updatedAt = Date()
    inboxThreadsByDocId[docId] = thread

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveInboxThread(thread)
    } catch {
      flashError("Failed to save thread: \(error.localizedDescription)")
      return
    }

    // Track as pending so auto-refresh won't overwrite it with stale data
    pendingThreadWrites[docId] = thread

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: delete thread message on \(docId)",
          autoPush: true
        )
        pendingThreadWrites.removeValue(forKey: docId)
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func updateInboxThreadTriage(docId: String, status: InboxTriageStatus) {
    guard let repoURL else { return }
    guard var thread = inboxThreadsByDocId[docId] else { return }

    thread.triageStatus = status
    thread.updatedAt = Date()
    inboxThreadsByDocId[docId] = thread

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveInboxThread(thread)
    } catch {
      flashError("Failed to save thread: \(error.localizedDescription)")
      return
    }

    // Track as pending so auto-refresh won't overwrite it with stale data
    pendingThreadWrites[docId] = thread

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update thread triage status to \(status.rawValue) on \(docId)",
          autoPush: true
        )
        pendingThreadWrites.removeValue(forKey: docId)
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
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

    if let repoURL = repoURL {
      do {
        let store = LobsControlStore(repoRoot: repoURL)
        try store.saveInboxThread(thread)
      } catch {
        flashError("Failed to save thread: \(error.localizedDescription)")
      }
    }
  }

  func selectTask(_ task: DashboardTask) {
    selectedTaskId = task.id
    popoverTaskId = task.id
    loadArtifactForSelected()
  }

  // MARK: - Optimistic + Async Helpers

  /// Show error banner that auto-dismisses after a few seconds.
  private func flashError(_ message: String) {
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

  /// Optimistically update a task locally, then do git work in background.
  /// On failure, reload from disk and show banner.
  private func optimisticUpdate(
    taskId: String,
    localMutation: (inout DashboardTask) -> Void,
    gitWork: @escaping (URL) async throws -> Void
  ) {
    guard let repoURL else { return }

    // 1. Apply local mutation immediately.
    if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
      withAnimation(.easeInOut(duration: 0.25)) {
        localMutation(&tasks[idx])
      }
    }

    // 2. Persist to disk synchronously (fast, local only).
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
        var t = tasks[idx]
        t.updatedAt = Date()
        tasks[idx] = t
        try store.saveExistingTask(t)
      }
    } catch {
      flashError("Failed to save: \(error.localizedDescription)")
      return
    }

    // 3. Git add/commit/push in background.
    isGitBusy = true
    Task {
      do {
        try await gitWork(repoURL)
      } catch {
        // Hold updated task in memory, pull --rebase, re-apply, retry.
        do {
          let taskSnapshot: DashboardTask? = tasks.first(where: { $0.id == taskId })
          _ = try await Git.runAsync(["pull", "--rebase"], cwd: repoURL)

          // Re-persist from memory after pull
          if let snapshot = taskSnapshot {
            let store = LobsControlStore(repoRoot: repoURL)
            try store.saveExistingTask(snapshot)
          }

          try await gitWork(repoURL)
        } catch {
          flashError("Git sync failed after retry: \(error.localizedDescription)")
          reload()
        }
      }
      isGitBusy = false
    }
  }

  // MARK: - Dependency Auto-Unblock

  /// When a task is completed, remove it from the `blockedBy` list of all dependent tasks.
  /// If a dependent task has no remaining blockers, auto-unblock it (set workState back from blocked).
  private func autoUnblockDependents(of completedTaskId: String, autoPush: Bool) {
    guard let repoURL else { return }
    let store = LobsControlStore(repoRoot: repoURL)

    for i in tasks.indices {
      guard var blockers = tasks[i].blockedBy, blockers.contains(completedTaskId) else { continue }
      blockers.removeAll { $0 == completedTaskId }
      tasks[i].blockedBy = blockers.isEmpty ? nil : blockers
      tasks[i].updatedAt = Date()

      // If no remaining blockers and task was blocked, unblock it
      if blockers.isEmpty && tasks[i].workState == .blocked {
        tasks[i].workState = .notStarted
      }

      do {
        try store.saveExistingTask(tasks[i])
      } catch {
        flashError("Failed to save unblocked task: \(error.localizedDescription)")
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
    }) { repoURL in
      // Also persist the status change to disk.
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setStatus(taskId: id, status: .active)
      try store.setWorkState(taskId: id, workState: .notStarted)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: approve \(id) → active",
        autoPush: autoPush
      )
    }
  }

  func requestChangesSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: { $0.reviewState = .changesRequested }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set \(id) reviewState=changes_requested",
        autoPush: autoPush
      )
    }
  }

  func rejectSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.reviewState = .rejected
      $0.status = .rejected
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setStatus(taskId: id, status: .rejected)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: reject \(id)",
        autoPush: autoPush
      )
    }
  }

  /// Mark an active task as completed (work is done).
  func completeSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.status = .completed
      $0.workState = nil
      if $0.finishedAt == nil { $0.finishedAt = Date() }
    }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: complete \(id)",
        autoPush: autoPush
      )
    }
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
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setStatus(taskId: id, status: .completed)
      try store.setReviewState(taskId: id, reviewState: .approved)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: mark \(id) done",
        autoPush: autoPush
      )
    }
  }

  /// Reopen a completed/rejected task back to Active.
  func reopenSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: {
      $0.status = .active
      $0.workState = .notStarted
      $0.reviewState = .approved
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setStatus(taskId: id, status: .active)
      try store.setWorkState(taskId: id, workState: .notStarted)
      try store.setReviewState(taskId: id, reviewState: .approved)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: reopen \(id) → active",
        autoPush: autoPush
      )
    }
  }

  /// Toggle blocked state on an active task.
  func toggleBlockSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    let currentlyBlocked = tasks.first(where: { $0.id == id })?.workState == .blocked
    let newState: WorkState = currentlyBlocked ? .inProgress : .blocked
    optimisticUpdate(taskId: id, localMutation: { $0.workState = newState }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setWorkState(taskId: id, workState: newState)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set \(id) workState=\(newState.rawValue)",
        autoPush: autoPush
      )
    }
  }

  func submitTaskToLobs(title: String, notes: String?, autoPush: Bool) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty, let repoURL else { return }

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
      finishedAt: nil
    )

    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      tasks.append(newTask)
      sortTasksForUX(&tasks)
    }

    // Ensure the newly-created task is selected for quick action.
    selectedTaskId = newTask.id
    popoverTaskId = newTask.id

    // Write to disk + async git.
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      _ = try store.addTask(
        id: newTask.id,
        title: trimmedTitle,
        owner: .lobs,
        status: .active,
        projectId: selectedProjectId,
        workState: .notStarted,
        reviewState: .approved,
        notes: trimmedNotes
      )
    } catch {
      flashError("Failed to save task: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        // Check if project uses GitHub sync mode
        let store = LobsControlStore(repoRoot: repoURL)
        if let project = projects.first(where: { $0.id == selectedProjectId }),
           project.syncMode == .github,
           let token = project.githubConfig?.accessToken, !token.isEmpty {
          // Create GitHub issue
          let updatedTask = try await store.saveTaskToGitHub(task: newTask, project: project, token: token)
          newTask = updatedTask

          // Update local task with GitHub issue number
          try store.saveExistingTask(updatedTask)

          // Update UI with GitHub issue number
          await MainActor.run {
            if let idx = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
              tasks[idx] = updatedTask
            }
          }
        }

        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: submit task \(newTask.id)",
          autoPush: autoPush
        )
      } catch {
        // Hold task data in memory, pull to resolve conflicts, then re-write and retry.
        do {
          let store = LobsControlStore(repoRoot: repoURL)
          let _ = try JSONEncoder().encode(newTask)

          // Pull --rebase (this may remove our new file, but we have it in memory)
          _ = try await Git.runAsync(["pull", "--rebase"], cwd: repoURL)

          // Re-write the task file from memory
          _ = try store.addTask(
            id: newTask.id,
            title: newTask.title,
            owner: newTask.owner,
            status: newTask.status,
            projectId: newTask.projectId,
            workState: newTask.workState,
            reviewState: newTask.reviewState,
            notes: newTask.notes
          )

          // Re-attempt commit + push
          try await asyncCommitAndMaybePush(
            repoURL: repoURL,
            message: "Lobs: submit task \(newTask.id)",
            autoPush: autoPush
          )
        } catch {
          flashError("Git sync failed after retry: \(error.localizedDescription)")
          reload()
        }
      }
      isGitBusy = false
    }
  }

  // MARK: - Projects

  // MARK: - Text Dumps

  func loadTextDumps(store: LobsControlStore? = nil) {
    guard let repoURL else { return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    do {
      textDumps = try s.loadTextDumps()
    } catch {
      textDumps = []
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
    guard let repoURL else { return }
    tasks.removeAll { $0.id == taskId }
    let store = LobsControlStore(repoRoot: repoURL)
    do {
      try store.deleteTask(taskId: taskId)
    } catch {
      flashError("Failed to delete task: \(error.localizedDescription)")
      return
    }
    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: delete task \(taskId)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  /// Update a task's title and notes (used from text dump results).
  func updateTaskTitleAndNotes(taskId: String, title: String, notes: String?) {
    editTask(taskId: taskId, title: title, notes: notes, autoPush: true)
  }

  func submitTextDump(text: String, projectId: String) {
    guard let repoURL else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let now = Date()
    let dump = TextDump(
      id: UUID().uuidString,
      projectId: projectId,
      text: trimmed,
      status: .pending,
      taskIds: nil,
      createdAt: now,
      updatedAt: now
    )

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveTextDump(dump)
    } catch {
      flashError("Failed to save text dump: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: text dump for project \(projectId)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
    }
  }

  // MARK: - Projects

  func createProject(title: String, notes: String?, type: ProjectType = .kanban) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty, let repoURL else { return }

    let id = uniqueProjectId(for: trimmedTitle)
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

    // Local update
    projects.append(p)
    selectedProjectId = p.id

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      var file = try store.loadProjects()
      // If file was synthesized (missing on disk), it will only contain Default.
      // Ensure default exists and then append.
      if !file.projects.contains(where: { $0.id == "default" }) {
        let dnow = Date()
        file.projects.insert(Project(id: "default", title: "Default", createdAt: dnow, updatedAt: dnow, notes: nil, archived: false), at: 0)
      }
      file.projects.append(p)
      file.generatedAt = Date()
      try store.saveProjects(file)

      // Keep README in sync with project notes (they are the same content)
      if let notes = trimmedNotes, !notes.isEmpty {
        try store.saveProjectReadme(projectId: id, content: notes)
      }
    } catch {
      flashError("Failed to save project: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: create project \(p.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
    }
  }

  func renameProject(id: String, newTitle: String) {
    let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let repoURL else { return }

    // Local update
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].title = trimmed
      projects[idx].updatedAt = Date()
    }

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.renameProject(id: id, newTitle: trimmed)
    } catch {
      flashError("Failed to rename project: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: rename project \(id) to \(trimmed)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
    }
  }

  func updateProjectNotes(id: String, notes: String?) {
    guard let repoURL else { return }
    let clean = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

    // Local update
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].notes = (clean?.isEmpty == true) ? nil : clean
      projects[idx].updatedAt = Date()
    }

    // Keep README in sync with project notes (they are the same content)
    if id == selectedProjectId {
      projectReadme = clean ?? ""
    }

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.updateProjectNotes(id: id, notes: clean)
      // Sync to README file as well
      try store.saveProjectReadme(projectId: id, content: clean ?? "")
    } catch {
      flashError("Failed to update project: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update project \(id) notes",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
    }
  }

  func updateProjectSyncMode(id: String, syncMode: SyncMode, githubConfig: GitHubConfig?) {
    guard let repoURL else { return }

    // Local update
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].syncMode = syncMode
      projects[idx].githubConfig = githubConfig
      projects[idx].updatedAt = Date()
    }

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.updateProjectSyncMode(id: id, syncMode: syncMode, githubConfig: githubConfig)
    } catch {
      flashError("Failed to update project sync mode: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        let modeStr = syncMode == .github ? "GitHub" : "local"
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update project \(id) sync mode to \(modeStr)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
    }
  }

  func deleteProject(id: String) {
    guard id != "default", let repoURL else { return }

    // Cascade delete: remove all tasks belonging to this project
    let taskIdsToDelete = tasks.filter { ($0.projectId ?? "default") == id }.map { $0.id }
    tasks.removeAll { ($0.projectId ?? "default") == id }

    // Remove locally
    projects.removeAll { $0.id == id }

    // Navigate back to home screen
    if selectedProjectId == id {
      selectedProjectId = "default"
      showOverview = true
    }

    // Persist cascade deletion + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)

      // Delete task files
      for taskId in taskIdsToDelete {
        try store.deleteTask(taskId: taskId)
      }

      // Delete research data (state/research/<projectId>/)
      try store.deleteResearchData(projectId: id)

      // Delete tracker data (state/tracker/<projectId>/)
      try store.deleteTrackerData(projectId: id)

      // Delete the project entry itself
      try store.deleteProject(id: id)
    } catch {
      flashError("Failed to delete project: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: delete project \(id) and all associated data",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
    }
  }

  func archiveProject(id: String) {
    guard id != "default", let repoURL else { return }

    // Local update
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].archived = true
      projects[idx].updatedAt = Date()
    }
    if selectedProjectId == id {
      selectedProjectId = "default"
    }

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.archiveProject(id: id)
    } catch {
      flashError("Failed to archive project: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: archive project \(id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
    }
  }

  func unarchiveProject(id: String) {
    guard let repoURL else { return }

    // Local update
    if let idx = projects.firstIndex(where: { $0.id == id }) {
      projects[idx].archived = false
      projects[idx].updatedAt = Date()
    }

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      var file = try store.loadProjects()
      if let idx = file.projects.firstIndex(where: { $0.id == id }) {
        file.projects[idx].archived = false
        file.projects[idx].updatedAt = Date()
      }
      file.generatedAt = Date()
      try store.saveProjects(file)
    } catch {
      flashError("Failed to unarchive project: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: unarchive project \(id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
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

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      var file = try store.loadProjects()
      for (i, project) in sorted.enumerated() {
        if let idx = file.projects.firstIndex(where: { $0.id == project.id }) {
          file.projects[idx].sortOrder = i
          file.projects[idx].updatedAt = Date()
        }
      }
      file.generatedAt = Date()
      try store.saveProjects(file)
    } catch {
      flashError("Failed to reorder projects: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: reorder projects",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
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

    // Persist + git
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      var file = try store.loadProjects()
      for (i, project) in sorted.enumerated() {
        if let idx = file.projects.firstIndex(where: { $0.id == project.id }) {
          file.projects[idx].sortOrder = i
          file.projects[idx].updatedAt = Date()
        }
      }
      file.generatedAt = Date()
      try store.saveProjects(file)
    } catch {
      flashError("Failed to reorder projects: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: reorder projects (drag)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
      }
      isGitBusy = false
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

    // Persist all affected tasks
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      for t in columnTasks {
        if let task = tasks.first(where: { $0.id == t.id }) {
          try store.setStatus(taskId: task.id, status: task.status)
          try store.setSortOrder(taskId: task.id, sortOrder: task.sortOrder)
        }
      }
    } catch {
      flashError("Failed to save reorder: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: reorder \(taskId) in \(status.rawValue)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
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
    guard let repoURL, !multiSelectedTaskIds.isEmpty else { return }
    let ids = multiSelectedTaskIds

    // Apply local mutations immediately
    for id in ids {
      if let idx = tasks.firstIndex(where: { $0.id == id }) {
        withAnimation(.easeInOut(duration: 0.25)) {
          tasks[idx].status = status
          tasks[idx].updatedAt = Date()
          if status == .completed {
            tasks[idx].workState = nil
            if tasks[idx].finishedAt == nil { tasks[idx].finishedAt = Date() }
          } else if status == .active {
            tasks[idx].workState = .notStarted
            if tasks[idx].startedAt == nil { tasks[idx].startedAt = Date() }
          }
        }
      }
    }

    // Persist to disk
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      for id in ids {
        if let task = tasks.first(where: { $0.id == id }) {
          try store.saveExistingTask(task)
        }
      }
    } catch {
      flashError("Failed to save bulk move: \(error.localizedDescription)")
      return
    }

    clearMultiSelect()

    // Git commit+push
    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: bulk move \(ids.count) tasks to \(status.rawValue)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }

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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      for id in ids {
        if let task = tasks.first(where: { $0.id == id }) {
          try store.saveExistingTask(task)
        }
      }
    } catch {
      flashError("Failed to save bulk approve: \(error.localizedDescription)")
      return
    }

    clearMultiSelect()

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: bulk approve \(ids.count) tasks",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      for id in ids {
        if let task = tasks.first(where: { $0.id == id }) {
          try store.saveExistingTask(task)
        }
      }
    } catch {
      flashError("Failed to save bulk reject: \(error.localizedDescription)")
      return
    }

    clearMultiSelect()

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: bulk reject \(ids.count) tasks",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  /// Toggle the pinned/starred state of a task.
  func togglePinTask(taskId: String, autoPush: Bool) {
    let currentlyPinned = tasks.first(where: { $0.id == taskId })?.pinned ?? false
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.pinned = !currentlyPinned ? true : nil
    }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: \(!currentlyPinned ? "pin" : "unpin") \(taskId)",
        autoPush: autoPush
      )
    }
  }

  func startTimer(taskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.startedAt = Date()
      $0.finishedAt = nil
      $0.updatedAt = Date()
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      guard let task = self.tasks.first(where: { $0.id == taskId }) else { return }
      try store.saveExistingTask(task)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: start timer \(taskId)",
        autoPush: autoPush
      )
    }
  }

  func stopTimer(taskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.finishedAt = Date()
      $0.updatedAt = Date()
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      guard let task = self.tasks.first(where: { $0.id == taskId }) else { return }
      try store.saveExistingTask(task)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: stop timer \(taskId)",
        autoPush: autoPush
      )
    }
  }

  func resetTimer(taskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.startedAt = nil
      $0.finishedAt = nil
      $0.updatedAt = Date()
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      guard let task = self.tasks.first(where: { $0.id == taskId }) else { return }
      try store.saveExistingTask(task)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: reset timer \(taskId)",
        autoPush: autoPush
      )
    }
  }

  func editTask(taskId: String, title: String, notes: String?, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { $0.title = t }
      let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
      $0.notes = (n?.isEmpty == true) ? nil : n
      $0.updatedAt = Date()
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setTitleAndNotes(taskId: taskId, title: title, notes: notes)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: edit \(taskId)",
        autoPush: autoPush
      )
    }
  }

  func setTaskShape(taskId: String, shape: TaskShape?, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      $0.shape = shape
      $0.updatedAt = Date()
    }) { repoURL in
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setTaskField(taskId: taskId, field: "shape", value: shape?.rawValue)
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set shape on \(taskId)",
        autoPush: autoPush
      )
    }
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
    }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: add blocker \(blockerTaskId) to \(taskId)",
        autoPush: autoPush
      )
    }
  }

  func removeBlocker(taskId: String, blockerTaskId: String, autoPush: Bool) {
    optimisticUpdate(taskId: taskId, localMutation: {
      var blockers = $0.blockedBy ?? []
      blockers.removeAll { $0 == blockerTaskId }
      $0.blockedBy = blockers.isEmpty ? nil : blockers
      if blockers.isEmpty && $0.workState == .blocked {
        $0.workState = .notStarted
      }
    }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: remove blocker \(blockerTaskId) from \(taskId)",
        autoPush: autoPush
      )
    }
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveTile(tile)
    } catch {
      flashError("Failed to save tile: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: add \(type.rawValue) tile \(tile.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func updateTile(_ tile: ResearchTile) {
    guard let repoURL else { return }
    var updated = tile
    updated.updatedAt = Date()

    if let idx = researchTiles.firstIndex(where: { $0.id == tile.id }) {
      researchTiles[idx] = updated
    }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveTile(updated)
    } catch {
      flashError("Failed to save tile: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update tile \(tile.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
    }
  }

  func removeTile(_ tile: ResearchTile) {
    guard let repoURL else { return }
    researchTiles.removeAll { $0.id == tile.id }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.deleteTile(projectId: tile.projectId, tileId: tile.id)
    } catch {
      flashError("Failed to delete tile: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: delete tile \(tile.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveRequest(req)
    } catch {
      flashError("Failed to save request: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: add research request \(req.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveRequest(updated)
    } catch {
      flashError("Failed to save request: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: update request \(request.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
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

  /// Assign a worker to a research request.
  func assignResearchRequestWorker(requestId: String, worker: String?) {
    guard let req = researchRequests.first(where: { $0.id == requestId }) else { return }
    var updated = req
    updated.assignedWorker = worker
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

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.saveRequest(sub)
    } catch {
      flashError("Failed to save sub-request: \(error.localizedDescription)")
      return
    }

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: split request \(parentId) → \(sub.id)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
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

  // MARK: - Async Git Helpers

  private func asyncCommitAndMaybePush(repoURL: URL, message: String, autoPush: Bool) async throws {
    let addResult = await Git.runAsyncWithErrorHandling(["add", "-A"], cwd: repoURL)
    if !addResult.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: addResult.error?.errorDescription ?? "Failed to stage changes"])
    }

    let stagedClean = await Git.runAsyncWithErrorHandling(["diff", "--cached", "--quiet"], cwd: repoURL)
    if stagedClean.success { return }

    let author = "Lobs <thelobsbot@gmail.com>"
    let committerEnv: [String: String] = [
      "GIT_COMMITTER_NAME": "Lobs",
      "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
    ]

    let commit = await Git.runAsyncWithErrorHandling([
      "commit", "--author", author, "-m", message
    ], cwd: repoURL, env: committerEnv)

    if !commit.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: commit.error?.errorDescription ?? "Commit failed"])
    }

    if autoPush {
      await MainActor.run {
        self.lastPushAttemptAt = Date()
      }

      let push = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
      if !push.success {
        // Push failed — pull --rebase and retry once if suggested.
        if push.suggestsPull {
          let pull = await Git.runWithRetry(["pull", "--rebase"], cwd: repoURL, maxRetries: 2)
          if !pull.success {
            let msg = pull.error?.errorDescription ?? "Pull failed"
            await MainActor.run {
              self.lastPushError = msg
            }
            throw NSError(domain: "Git", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
          }
          let retry = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
          if !retry.success {
            let msg = retry.error?.errorDescription ?? "Push failed"
            await MainActor.run {
              self.lastPushError = msg
            }
            throw NSError(domain: "Git", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
          }
        } else {
          let msg = push.error?.errorDescription ?? "Push failed"
          await MainActor.run {
            self.lastPushError = msg
          }
          throw NSError(domain: "Git", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: msg])
        }
      }

      // Get current commit hash for display
      let hashResult = await Git.runAsyncWithErrorHandling(["rev-parse", "--short", "HEAD"], cwd: repoURL)
      let commitHash = hashResult.success ? hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil

      await MainActor.run {
        self.lastSuccessfulPushAt = Date()
        self.lastPushedCommitHash = commitHash
        self.lastPushError = nil
      }
    }
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

  private func syncRepo(repoURL: URL) throws {
    let remotes = Git.runWithErrorHandling(["remote"], cwd: repoURL)
    if !remotes.success { return }
    let hasOrigin = remotes.output.split(separator: "\n").map(String.init).contains("origin")
    if !hasOrigin { return }

    // Auto-commit local changes so sync can proceed (instead of silently skipping).
    let status = Git.runWithErrorHandling(["status", "--porcelain"], cwd: repoURL)
    let hasLocalChanges = status.success
      && !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    if hasLocalChanges {
      try autoCommitLocalChanges(repoURL: repoURL)
    }
    syncBlockedByUncommitted = false

    let fetchResult = Git.runWithErrorHandling(["fetch", "origin"], cwd: repoURL)
    if !fetchResult.success {
      print("[sync] git fetch failed: \(fetchResult.error?.errorDescription ?? "Unknown error")")
      return
    }

    // Decide whether to rebase vs hard-reset.
    // If local HEAD is ahead of origin/main (even with a clean working tree), we must rebase,
    // not reset, or we'd discard local commits.
    let aheadRes = Git.runWithErrorHandling(["rev-list", "--count", "origin/main..HEAD"], cwd: repoURL)
    let behindRes = Git.runWithErrorHandling(["rev-list", "--count", "HEAD..origin/main"], cwd: repoURL)
    let aheadCount = Int(aheadRes.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    let behindCount = Int(behindRes.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

    if hasLocalChanges || aheadCount > 0 {
      // Rebase local commits on top of remote to preserve them.
      let rebase = Git.runWithErrorHandling(["rebase", "origin/main"], cwd: repoURL)
      if !rebase.success {
        _ = Git.runWithErrorHandling(["rebase", "--abort"], cwd: repoURL)
        syncBlockedByUncommitted = true
        print("[sync] rebase conflict: \(rebase.error?.errorDescription ?? "Unknown error")")
        return
      }
    } else if behindCount > 0 {
      let resetResult = Git.runWithErrorHandling(["reset", "--hard", "origin/main"], cwd: repoURL)
      if !resetResult.success {
        print("[sync] git reset failed: \(resetResult.error?.errorDescription ?? "Unknown error")")
        return
      }
      _ = Git.runWithErrorHandling(["clean", "-fd"], cwd: repoURL)
    }
  }

  /// Async version of syncRepo — runs git commands off the main thread to avoid UI lag.
  private func syncRepoAsync(repoURL: URL) async throws {
    let remotes = await Git.runAsyncWithErrorHandling(["remote"], cwd: repoURL)
    if !remotes.success { return }
    let hasOrigin = remotes.output.split(separator: "\n").map(String.init).contains("origin")
    if !hasOrigin { return }

    // Auto-commit local changes so sync can proceed.
    let status = await Git.runAsyncWithErrorHandling(["status", "--porcelain"], cwd: repoURL)
    let hasLocalChanges = status.success
      && !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    if hasLocalChanges {
      try await autoCommitLocalChangesAsync(repoURL: repoURL)
    }
    syncBlockedByUncommitted = false

    // Fetch with retry (network operation)
    let fetch = await Git.runWithRetry(["fetch", "origin"], cwd: repoURL, maxRetries: 3)
    if !fetch.success {
      print("[sync] git fetch failed: \(fetch.error?.errorDescription ?? "Unknown error")")
      return
    }

    // Decide whether to rebase vs hard-reset.
    // If local HEAD is ahead of origin/main (even with a clean working tree), we must rebase,
    // not reset, or we'd discard local commits.
    let aheadRes = await Git.runAsyncWithErrorHandling(["rev-list", "--count", "origin/main..HEAD"], cwd: repoURL)
    let behindRes = await Git.runAsyncWithErrorHandling(["rev-list", "--count", "HEAD..origin/main"], cwd: repoURL)
    let aheadCount = Int(aheadRes.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    let behindCount = Int(behindRes.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

    if hasLocalChanges || aheadCount > 0 {
      let rebase = await Git.runAsyncWithErrorHandling(["rebase", "origin/main"], cwd: repoURL)
      if !rebase.success {
        _ = await Git.runAsyncWithErrorHandling(["rebase", "--abort"], cwd: repoURL)
        syncBlockedByUncommitted = true
        print("[sync] rebase conflict — sync blocked: \(rebase.error?.errorDescription ?? "Unknown error")")
        return
      }
    } else if behindCount > 0 {
      let reset = await Git.runAsyncWithErrorHandling(["reset", "--hard", "origin/main"], cwd: repoURL)
      if !reset.success {
        print("[sync] git reset failed: \(reset.error?.errorDescription ?? "Unknown error")")
        return
      }
      _ = await Git.runAsyncWithErrorHandling(["clean", "-fd"], cwd: repoURL)
    }
  }

  /// Auto-commit any uncommitted changes with a standard message before sync.
  private func autoCommitLocalChanges(repoURL: URL) throws {
    let author = "Lobs <thelobsbot@gmail.com>"
    let committerEnv: [String: String] = [
      "GIT_COMMITTER_NAME": "Lobs",
      "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
    ]
    let addResult = Git.runWithErrorHandling(["add", "-A"], cwd: repoURL)
    if !addResult.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: addResult.error?.errorDescription ?? "Failed to stage changes"])
    }
    let commitResult = Git.runWithErrorHandling([
      "commit", "--author", author, "-m", "Auto-commit local changes before sync"
    ], cwd: repoURL, env: committerEnv)
    if !commitResult.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: commitResult.error?.errorDescription ?? "Failed to commit changes"])
    }
  }

  /// Async version of autoCommitLocalChanges.
  private func autoCommitLocalChangesAsync(repoURL: URL) async throws {
    let author = "Lobs <thelobsbot@gmail.com>"
    let committerEnv: [String: String] = [
      "GIT_COMMITTER_NAME": "Lobs",
      "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
    ]
    let addResult = await Git.runAsyncWithErrorHandling(["add", "-A"], cwd: repoURL)
    if !addResult.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: addResult.error?.errorDescription ?? "Failed to stage changes"])
    }
    let commitResult = await Git.runAsyncWithErrorHandling([
      "commit", "--author", author, "-m", "Auto-commit local changes before sync"
    ], cwd: repoURL, env: committerEnv)
    if !commitResult.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: commitResult.error?.errorDescription ?? "Failed to commit changes"])
    }
  }

  private func commitAndMaybePush(repoURL: URL, message: String, autoPush: Bool) throws {
    let addResult = Git.runWithErrorHandling(["add", "-A"], cwd: repoURL)
    if !addResult.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: addResult.error?.errorDescription ?? "Failed to stage changes"])
    }

    let stagedClean = Git.runWithErrorHandling(["diff", "--cached", "--quiet"], cwd: repoURL)
    if stagedClean.success { return }

    let author = "Lobs <thelobsbot@gmail.com>"
    let committerEnv: [String: String] = [
      "GIT_COMMITTER_NAME": "Lobs",
      "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
    ]

    let commit = Git.runWithErrorHandling([
      "commit", "--author", author, "-m", message
    ], cwd: repoURL, env: committerEnv)

    if !commit.success {
      throw NSError(domain: "Git", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: commit.error?.errorDescription ?? "Commit failed"])
    }

    if autoPush {
      let push = Git.runWithErrorHandling(["push"], cwd: repoURL)
      if !push.success {
        // Push failed — pull --rebase and retry once if suggested.
        if push.suggestsPull {
          let pull = Git.runWithErrorHandling(["pull", "--rebase"], cwd: repoURL)
          if !pull.success {
            throw NSError(domain: "Git", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: pull.error?.errorDescription ?? "Pull failed"])
          }
          let retry = Git.runWithErrorHandling(["push"], cwd: repoURL)
          if !retry.success {
            throw NSError(domain: "Git", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: retry.error?.errorDescription ?? "Push failed"])
          }
        } else {
          throw NSError(domain: "Git", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: push.error?.errorDescription ?? "Push failed"])
        }
      }
    }
  }

  // Drag-and-drop support
  @Published var draggingTaskId: String? = nil

  var filteredTasks: [DashboardTask] {
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

    return out
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

  func loadArtifactForSelected() {
    guard let repoURL else { return }
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try loadArtifactForSelected(store: store)
    } catch {
      lastError = String(describing: error)
    }
  }

  private func loadArtifactForSelected(store: LobsControlStore) throws {
    if let id = selectedTaskId, let t = tasks.first(where: { $0.id == id }), let ap = t.artifactPath {
      artifactText = try store.readArtifact(relativePath: ap)
    } else {
      artifactText = "(select a task)"
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
}
