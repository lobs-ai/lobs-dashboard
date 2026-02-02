import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
  private let settings = UserDefaults.standard

  // UserDefaults keys
  private let repoPathKey = "repoPath"
  private let ownerFilterKey = "ownerFilter"
  private let wipLimitActiveKey = "wipLimitActive"
  private let completedShowRecentKey = "completedShowRecent"
  private let autoArchiveCompletedKey = "autoArchiveCompleted"
  private let archiveCompletedAfterDaysKey = "archiveCompletedAfterDays"
  private let autoRefreshEnabledKey = "autoRefreshEnabled"
  private let autoRefreshIntervalSecondsKey = "autoRefreshIntervalSeconds"
  private let selectedProjectIdKey = "selectedProjectId"

  @Published private(set) var repoPath: String = ""

  @Published var tasks: [DashboardTask] = []
  @Published var selectedTaskId: String? = nil

  // Research
  @Published var researchTiles: [ResearchTile] = []
  @Published var researchRequests: [ResearchRequest] = []
  @Published var selectedTileId: String? = nil

  // Tracker
  @Published var trackerItems: [TrackerItem] = []

  // Inbox (Design Docs)
  @Published var inboxItems: [InboxItem] = []
  @Published var readItemIds: Set<String> = [] {
    didSet {
      settings.set(Array(readItemIds), forKey: "readInboxItemIds")
    }
  }
  @Published var showInbox: Bool = false
  @Published var inboxResponsesByDocId: [String: InboxResponse] = [:]
  @Published var inboxThreadsByDocId: [String: InboxThread] = [:]

  // Project README
  @Published var projectReadme: String = ""

  // Worker Status
  @Published var workerStatus: WorkerStatus? = nil

  // Projects
  @Published var projects: [Project] = []
  @Published var selectedProjectId: String = "default" {
    didSet {
      settings.set(selectedProjectId, forKey: selectedProjectIdKey)
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

  /// Whether a background git operation is in flight.
  @Published var isGitBusy: Bool = false

  // Kanban UX
  @Published var searchText: String = ""

  /// Inbox is treated as a filter, not a column.
  @Published var showInboxOnly: Bool = false
  @Published var ownerFilter: String = "all" {
    didSet { settings.set(ownerFilter, forKey: ownerFilterKey) }
  }
  @Published var wipLimitActive: Int = 6 {
    didSet { settings.set(wipLimitActive, forKey: wipLimitActiveKey) }
  }

  // Completed hygiene
  @Published var completedShowRecent: Int = 30 {
    didSet { settings.set(completedShowRecent, forKey: completedShowRecentKey) }
  }
  @Published var autoArchiveCompleted: Bool = false {
    didSet { settings.set(autoArchiveCompleted, forKey: autoArchiveCompletedKey) }
  }
  @Published var archiveCompletedAfterDays: Int = 30 {
    didSet { settings.set(archiveCompletedAfterDays, forKey: archiveCompletedAfterDaysKey) }
  }

  // Popover state for task detail
  @Published var popoverTaskId: String? = nil

  // Auto-refresh
  @Published var autoRefreshEnabled: Bool = true {
    didSet { settings.set(autoRefreshEnabled, forKey: autoRefreshEnabledKey) }
  }
  @Published var autoRefreshIntervalSeconds: Int = 30 {
    didSet { settings.set(autoRefreshIntervalSeconds, forKey: autoRefreshIntervalSecondsKey) }
  }
  private var refreshTimer: Timer?

  init() {
    repoPath = settings.string(forKey: repoPathKey) ?? ""
    selectedProjectId = settings.string(forKey: selectedProjectIdKey) ?? "default"

    // Load persisted settings (with safe defaults)
    ownerFilter = settings.string(forKey: ownerFilterKey) ?? "all"

    let wip = settings.integer(forKey: wipLimitActiveKey)
    wipLimitActive = (wip == 0) ? 6 : wip

    let csr = settings.integer(forKey: completedShowRecentKey)
    completedShowRecent = (csr == 0) ? 30 : csr

    autoArchiveCompleted = settings.bool(forKey: autoArchiveCompletedKey)

    let days = settings.integer(forKey: archiveCompletedAfterDaysKey)
    archiveCompletedAfterDays = (days == 0) ? 30 : days

    // Default true if unset
    autoRefreshEnabled = settings.object(forKey: autoRefreshEnabledKey) as? Bool ?? true

    let interval = settings.integer(forKey: autoRefreshIntervalSecondsKey)
    autoRefreshIntervalSeconds = (interval == 0) ? 30 : interval

    // Inbox read state
    readItemIds = Set(settings.stringArray(forKey: "readInboxItemIds") ?? [])

    startAutoRefreshIfNeeded()
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
        self?.silentReload()
      }
    }
  }

  private func sortTasksForUX(_ tasks: inout [DashboardTask]) {
    // Stable ordering for UX.
    // Respect manual sortOrder first, then fall back to creation time.
    tasks.sort { (a, b) in
      if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
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
        let file = try store.loadTasks()
        // Only update if something changed (avoid UI flicker).
        if file.tasks.map({ $0.id }).sorted() != tasks.map({ $0.id }).sorted()
          || file.tasks.map({ $0.updatedAt }) != tasks.map({ $0.updatedAt }) {
          tasks = file.tasks
          try loadArtifactForSelected(store: store)
        }

        // Refresh research data too
        loadResearchData(store: store)
        loadTrackerData(store: store)
        loadInboxItems(store: store)
      } catch {
        // Silent — don't overwrite errors from user actions.
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
    settings.set(repoPath, forKey: repoPathKey)
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

        let file = try store.loadTasks()
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

      } catch {
        lastError = String(describing: error)
      }
      isGitBusy = false
    }
  }

  func loadResearchData(store: LobsControlStore? = nil) {
    guard let repoURL else { return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    guard isResearchProject else {
      researchTiles = []
      researchRequests = []
      return
    }
    do {
      researchTiles = try s.loadTiles(projectId: selectedProjectId)
      researchRequests = try s.loadRequests(projectId: selectedProjectId)
    } catch {
      flashError("Failed to load research data: \(error.localizedDescription)")
    }
  }

  // MARK: - Tracker

  func loadTrackerData(store: LobsControlStore? = nil) {
    guard let repoURL else { return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    guard isTrackerProject else {
      trackerItems = []
      return
    }
    do {
      trackerItems = try s.loadTrackerItems(projectId: selectedProjectId)
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

      inboxThreadsByDocId = try s.loadAllInboxThreads()
    } catch {
      flashError("Failed to load inbox: \(error.localizedDescription)")
    }
  }

  func markInboxItemRead(_ item: InboxItem) {
    readItemIds.insert(item.id)
    if let idx = inboxItems.firstIndex(where: { $0.id == item.id }) {
      inboxItems[idx].isRead = true
    }
  }

  func markInboxItemUnread(_ item: InboxItem) {
    readItemIds.remove(item.id)
    if let idx = inboxItems.firstIndex(where: { $0.id == item.id }) {
      inboxItems[idx].isRead = false
    }
  }

  var unreadInboxCount: Int {
    inboxItems.filter { !$0.isRead }.count
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
    guard let repoURL else { workerStatus = nil; return }
    let s = store ?? LobsControlStore(repoRoot: repoURL)
    do {
      workerStatus = try s.loadWorkerStatus()
    } catch {
      workerStatus = nil
    }
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

    isGitBusy = true
    Task {
      do {
        try await asyncCommitAndMaybePush(
          repoURL: repoURL,
          message: "Lobs: thread reply on \(docId)",
          autoPush: true
        )
      } catch {
        flashError("Git push failed: \(error.localizedDescription)")
      }
      isGitBusy = false
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
    let newTask = DashboardTask(
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
        if t.status == .active { return true }
        if case .other = t.status { return true }
        return false
      case .waitingOn: return t.status == .waitingOn
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

  func addRequest(prompt: String, tileId: String? = nil) {
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

  // MARK: - Async Git Helpers

  private func asyncCommitAndMaybePush(repoURL: URL, message: String, autoPush: Bool) async throws {
    _ = try await Git.runAsync(["add", "-A"], cwd: repoURL)

    let stagedClean = try await Git.runAsync(["diff", "--cached", "--quiet"], cwd: repoURL)
    if stagedClean.exitCode == 0 { return }

    let author = "Lobs <thelobsbot@gmail.com>"
    let committerEnv: [String: String] = [
      "GIT_COMMITTER_NAME": "Lobs",
      "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
    ]

    let commit = try await Git.runAsync([
      "commit", "--author", author, "-m", message
    ], cwd: repoURL, env: committerEnv)

    if commit.exitCode != 0 {
      throw NSError(domain: "Git", code: Int(commit.exitCode),
                    userInfo: [NSLocalizedDescriptionKey: commit.stderr])
    }

    if autoPush {
      let push = try await Git.runAsync(["push"], cwd: repoURL)
      if push.exitCode != 0 {
        // Push failed — pull --rebase and retry once.
        let pull = try await Git.runAsync(["pull", "--rebase"], cwd: repoURL)
        if pull.exitCode != 0 {
          throw NSError(domain: "Git", code: Int(pull.exitCode),
                        userInfo: [NSLocalizedDescriptionKey: "Pull --rebase failed: \(pull.stderr)"])
        }
        let retry = try await Git.runAsync(["push"], cwd: repoURL)
        if retry.exitCode != 0 {
          throw NSError(domain: "Git", code: Int(retry.exitCode),
                        userInfo: [NSLocalizedDescriptionKey: retry.stderr])
        }
      }
    }
  }

  private func syncRepo(repoURL: URL) throws {
    let remotes = try Git.run(["remote"], cwd: repoURL)
    if remotes.exitCode != 0 { return }
    let hasOrigin = remotes.stdout.split(separator: "\n").map(String.init).contains("origin")
    if !hasOrigin { return }

    // Safety: never hard-reset if there are local changes (e.g. a newly-created task) —
    // otherwise a transient git failure can appear to "delete" the user's work.
    let status = try Git.run(["status", "--porcelain"], cwd: repoURL)
    if status.exitCode == 0 && !status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return
    }

    _ = try Git.run(["fetch", "origin"], cwd: repoURL)
    _ = try Git.run(["reset", "--hard", "origin/main"], cwd: repoURL)
    _ = try Git.run(["clean", "-fd"], cwd: repoURL)
  }

  /// Async version of syncRepo — runs git commands off the main thread to avoid UI lag.
  private func syncRepoAsync(repoURL: URL) async throws {
    let remotes = try await Git.runAsync(["remote"], cwd: repoURL)
    if remotes.exitCode != 0 { return }
    let hasOrigin = remotes.stdout.split(separator: "\n").map(String.init).contains("origin")
    if !hasOrigin { return }

    let status = try await Git.runAsync(["status", "--porcelain"], cwd: repoURL)
    if status.exitCode == 0 && !status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return
    }

    _ = try await Git.runAsync(["fetch", "origin"], cwd: repoURL)
    _ = try await Git.runAsync(["reset", "--hard", "origin/main"], cwd: repoURL)
    _ = try await Git.runAsync(["clean", "-fd"], cwd: repoURL)
  }

  private func commitAndMaybePush(repoURL: URL, message: String, autoPush: Bool) throws {
    _ = try Git.run(["add", "-A"], cwd: repoURL)

    let stagedClean = try Git.run(["diff", "--cached", "--quiet"], cwd: repoURL)
    if stagedClean.exitCode == 0 { return }

    let author = "Lobs <thelobsbot@gmail.com>"
    let committerEnv: [String: String] = [
      "GIT_COMMITTER_NAME": "Lobs",
      "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
    ]

    let commit = try Git.run([
      "commit", "--author", author, "-m", message
    ], cwd: repoURL, env: committerEnv)

    if commit.exitCode != 0 {
      throw NSError(domain: "Git", code: Int(commit.exitCode),
                    userInfo: [NSLocalizedDescriptionKey: commit.stderr])
    }

    if autoPush {
      let push = try Git.run(["push"], cwd: repoURL)
      if push.exitCode != 0 {
        // Push failed — pull --rebase and retry once.
        let pull = try Git.run(["pull", "--rebase"], cwd: repoURL)
        if pull.exitCode != 0 {
          throw NSError(domain: "Git", code: Int(pull.exitCode),
                        userInfo: [NSLocalizedDescriptionKey: "Pull --rebase failed: \(pull.stderr)"])
        }
        let retry = try Git.run(["push"], cwd: repoURL)
        if retry.exitCode != 0 {
          throw NSError(domain: "Git", code: Int(retry.exitCode),
                        userInfo: [NSLocalizedDescriptionKey: retry.stderr])
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

    return out
  }

  var columns: [AnyTaskColumn] {
    [
      .init(title: "Active", dropStatus: .active) { t in
        if t.status == .active { return true }
        // Unknown statuses default to Active column
        switch t.status {
        case .inbox, .active, .waitingOn, .completed, .rejected:
          return false
        case .other:
          return true
        }
      },
      .init(title: "Waiting on", dropStatus: .waitingOn) { $0.status == .waitingOn },

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

  func selectNextTask() {
    let visible = filteredTasks
    guard !visible.isEmpty else { return }
    if let current = selectedTaskId, let idx = visible.firstIndex(where: { $0.id == current }) {
      let next = min(idx + 1, visible.count - 1)
      selectTask(visible[next])
    } else {
      selectTask(visible[0])
    }
  }

  func selectPreviousTask() {
    let visible = filteredTasks
    guard !visible.isEmpty else { return }
    if let current = selectedTaskId, let idx = visible.firstIndex(where: { $0.id == current }) {
      let prev = max(idx - 1, 0)
      selectTask(visible[prev])
    } else {
      selectTask(visible[visible.count - 1])
    }
  }

  // App icon is bundled in Resources/AppIcon.png (no user customization).
}
