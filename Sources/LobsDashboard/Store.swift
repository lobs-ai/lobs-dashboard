import CryptoKit
import Foundation

enum StoreError: Error, LocalizedError {
  case missingGitHubConfig

  var errorDescription: String? {
    switch self {
    case .missingGitHubConfig:
      return "Project is configured for GitHub sync but missing GitHub configuration"
    }
  }
}

// MARK: - GitHub Cache Models

/// Cached GitHub issue structure (matches gh-sync output format).
struct CachedGitHubIssue: Codable {
  let number: Int
  let title: String
  let body: String
  let labels: [String]
  let state: String
  let assignees: [String]
}

/// GitHub issue cache file structure.
struct GitHubIssueCache: Codable {
  let repo: String
  let fetchedAt: String
  let issues: [CachedGitHubIssue]
}

final class LobsControlStore {
  let repoRoot: URL

  init(repoRoot: URL) {
    self.repoRoot = repoRoot
  }

  private var tasksURL: URL { repoRoot.appendingPathComponent("state/tasks.json") }
  private var tasksDirURL: URL { repoRoot.appendingPathComponent("state/tasks") }
  private var archiveDirURL: URL { repoRoot.appendingPathComponent("state/tasks-archive") }

  private var projectsURL: URL { repoRoot.appendingPathComponent("state/projects.json") }
  private var researchDirURL: URL { repoRoot.appendingPathComponent("state/research") }

  private var trackerDirURL: URL { repoRoot.appendingPathComponent("state/tracker") }

  private func trackerItemsDirURL(projectId: String) -> URL {
    trackerDirURL.appendingPathComponent(projectId).appendingPathComponent("items")
  }

  private func tilesDirURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("tiles")
  }

  private func requestsDirURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("requests")
  }

  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let str = try container.decode(String.self)
      // Try standard ISO 8601 first
      let isoFormatter = ISO8601DateFormatter()
      isoFormatter.formatOptions = [.withInternetDateTime]
      if let date = isoFormatter.date(from: str) { return date }
      // Try with fractional seconds
      isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = isoFormatter.date(from: str) { return date }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
    }
    return d
  }

  private func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
  }

  /// Encode value to JSON with Python-compatible formatting (": " instead of " : ").
  private func encodeToPythonJSON<T: Encodable>(_ value: T) throws -> Data {
    let data = try encoder().encode(value)
    guard var jsonString = String(data: data, encoding: .utf8) else {
      return data
    }
    // Replace Swift's " : " with Python's ": "
    jsonString = jsonString.replacingOccurrences(of: " : ", with: ": ")
    return Data(jsonString.utf8)
  }

  private func taskFileURL(taskId: String) -> URL {
    tasksDirURL.appendingPathComponent("\(taskId).json")
  }

  // MARK: - Projects

  func loadProjects() throws -> ProjectsFile {
    let fm = FileManager.default

    // If missing, synthesize a default project (in-memory) but do not write until user creates/edits.
    guard fm.fileExists(atPath: projectsURL.path) else {
      let now = Date()
      return ProjectsFile(
        schemaVersion: 1,
        generatedAt: now,
        projects: [Project(id: "default", title: "Default", createdAt: now, updatedAt: now, notes: nil, archived: false)]
      )
    }

    let data = try Data(contentsOf: projectsURL)
    return try decoder().decode(ProjectsFile.self, from: data)
  }

  func saveProjects(_ file: ProjectsFile) throws {
    // Don't unconditionally update generatedAt - let callers update it when they make changes
    // This prevents spurious git diffs when nothing actually changed
    try FileManager.default.createDirectory(
      at: projectsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let data = try encodeToPythonJSON(file)
    try data.write(to: projectsURL, options: [.atomic])
  }

  func renameProject(id: String, newTitle: String) throws {
    var file = try loadProjects()
    guard let idx = file.projects.firstIndex(where: { $0.id == id }) else { return }
    let newTitleTrimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard file.projects[idx].title != newTitleTrimmed else { return } // No change
    file.projects[idx].title = newTitleTrimmed
    file.projects[idx].updatedAt = Date()
    file.generatedAt = Date()
    try saveProjects(file)
  }

  func updateProjectNotes(id: String, notes: String?) throws {
    var file = try loadProjects()
    guard let idx = file.projects.firstIndex(where: { $0.id == id }) else { return }
    let clean = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanNotes = (clean?.isEmpty == true) ? nil : clean
    guard file.projects[idx].notes != cleanNotes else { return } // No change
    file.projects[idx].notes = cleanNotes
    file.projects[idx].updatedAt = Date()
    file.generatedAt = Date()
    try saveProjects(file)
  }

  func updateProjectSyncMode(id: String, syncMode: SyncMode, githubConfig: GitHubConfig?) throws {
    var file = try loadProjects()
    guard let idx = file.projects.firstIndex(where: { $0.id == id }) else { return }
    file.projects[idx].syncMode = syncMode
    file.projects[idx].githubConfig = githubConfig
    file.projects[idx].updatedAt = Date()
    file.generatedAt = Date()
    try saveProjects(file)
  }

  func deleteProject(id: String) throws {
    var file = try loadProjects()
    let oldCount = file.projects.count
    file.projects.removeAll { $0.id == id }
    guard file.projects.count != oldCount else { return } // No change
    file.generatedAt = Date()
    try saveProjects(file)
  }

  func archiveProject(id: String) throws {
    var file = try loadProjects()
    guard let idx = file.projects.firstIndex(where: { $0.id == id }) else { return }
    guard file.projects[idx].archived != true else { return } // Already archived
    file.projects[idx].archived = true
    file.projects[idx].updatedAt = Date()
    file.generatedAt = Date()
    try saveProjects(file)
  }

  // MARK: - Tasks

  /// Load local tasks from JSON files (synchronous) wrapped in TasksFile for legacy methods.
  private func loadLocalTasksFile() throws -> TasksFile {
    let tasks = try loadLocalTasks()
    // Apply stable ordering
    var sortedTasks = tasks
    sortedTasks.sort { (a, b) in
      if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
      let oa = a.sortOrder ?? Int.max
      let ob = b.sortOrder ?? Int.max
      if oa != ob { return oa < ob }
      if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
      return a.updatedAt > b.updatedAt
    }
    return TasksFile(schemaVersion: 0, generatedAt: Date(), tasks: sortedTasks)
  }

  /// Load local tasks from JSON files (synchronous).
  func loadLocalTasks() throws -> [DashboardTask] {
    // Prefer per-task files if the directory exists.
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let items = try FileManager.default.contentsOfDirectory(
        at: tasksDirURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )

      let dec = decoder()
      var tasks: [DashboardTask] = []

      for url in items where url.pathExtension.lowercased() == "json" {
        let data = try Data(contentsOf: url)
        let t = try dec.decode(DashboardTask.self, from: data)
        tasks.append(t)
      }

      return tasks
    }

    // Fallback: legacy single file.
    let data = try Data(contentsOf: tasksURL)
    let file = try decoder().decode(TasksFile.self, from: data)
    return file.tasks
  }

  /// Load tasks with dual-mode support (local + GitHub).
  func loadTasks() async throws -> TasksFile {
    // Load local tasks first
    var allTasks = try loadLocalTasks()

    // Load projects to check for GitHub sync mode
    let projectsFile = try loadProjects()

    // For each project with GitHub mode, load and merge tasks from cache
    for project in projectsFile.projects where project.tracking == .github {
      do {
        let githubTasks = try loadTasksFromGitHubCache(project: project)

        // Merge GitHub tasks with local tasks
        // Strategy: match by githubIssueNumber; prefer local for conflicts; add unmatched GitHub tasks
        let localTasksByIssueNumber = Dictionary(
          uniqueKeysWithValues: allTasks.compactMap { task -> (Int, DashboardTask)? in
            guard task.projectId == project.id, let issueNumber = task.githubIssueNumber else { return nil }
            return (issueNumber, task)
          }
        )

        for githubTask in githubTasks {
          if let issueNumber = githubTask.githubIssueNumber,
             localTasksByIssueNumber[issueNumber] != nil {
            // Task exists locally - keep local version as source of truth
            continue
          } else {
            // New task from GitHub - add it
            allTasks.append(githubTask)
          }
        }
      } catch {
        // Log error but continue loading other projects
        print("Warning: Failed to load GitHub tasks for project \(project.title): \(error)")
      }
    }

    // Stable ordering (nice UX)
    // Respect manual sortOrder first, then fall back to creation time.
    allTasks.sort { (a, b) in
      if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
      let oa = a.sortOrder ?? Int.max
      let ob = b.sortOrder ?? Int.max
      if oa != ob { return oa < ob }
      if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
      return a.updatedAt > b.updatedAt
    }

    return TasksFile(schemaVersion: 0, generatedAt: Date(), tasks: allTasks)
  }

  func saveTasks(_ file: TasksFile) throws {
    // If per-task directory exists, write each task to its own file.
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      try FileManager.default.createDirectory(
        at: tasksDirURL,
        withIntermediateDirectories: true
      )

      for task in file.tasks {
        let data = try encodeToPythonJSON(task)
        try data.write(to: taskFileURL(taskId: task.id), options: [.atomic])
      }

      // Keep legacy tasks.json updated too (helps older tooling).
      var legacy = file
      legacy.generatedAt = Date()
      let legacyData = try encodeToPythonJSON(legacy)
      try FileManager.default.createDirectory(
        at: tasksURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try legacyData.write(to: tasksURL, options: [.atomic])
      return
    }

    // Legacy mode
    var file = file
    file.generatedAt = Date()

    let data = try encodeToPythonJSON(file)

    try FileManager.default.createDirectory(
      at: tasksURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    try data.write(to: tasksURL, options: [.atomic])
  }

  /// Load tasks from GitHub Issues for a project.
  /// Load GitHub issues from local cache (populated by gh-sync script).
  func loadTasksFromGitHubCache(project: Project) throws -> [DashboardTask] {
    guard let config = project.githubConfig else {
      throw StoreError.missingGitHubConfig
    }

    // Parse owner/repo from config.repo (format: "owner/repo")
    let parts = config.repo.split(separator: "/")
    guard parts.count == 2 else {
      throw StoreError.missingGitHubConfig
    }
    let owner = String(parts[0])
    let repo = String(parts[1])

    // Read from cache
    let cacheKey = "\(owner)-\(repo)"
    let cachePath = repoRoot
      .appendingPathComponent("state/cache/github")
      .appendingPathComponent(cacheKey)
      .appendingPathComponent("issues.json")

    guard FileManager.default.fileExists(atPath: cachePath.path) else {
      // Cache doesn't exist yet - return empty array
      return []
    }

    let data = try Data(contentsOf: cachePath)
    let cache = try decoder().decode(GitHubIssueCache.self, from: data)

    var tasks: [DashboardTask] = []
    for cachedIssue in cache.issues {
      let task = try mapCachedIssueToTask(issue: cachedIssue, projectId: project.id, repo: config.repo)
      tasks.append(task)
    }

    return tasks
  }

  /// Get the last sync timestamp for a GitHub project cache.
  func getGitHubCacheTimestamp(project: Project) -> Date? {
    guard let config = project.githubConfig else { return nil }

    let parts = config.repo.split(separator: "/")
    guard parts.count == 2 else { return nil }
    let owner = String(parts[0])
    let repo = String(parts[1])

    let cacheKey = "\(owner)-\(repo)"
    let timestampPath = repoRoot
      .appendingPathComponent("state/cache/github")
      .appendingPathComponent(cacheKey)
      .appendingPathComponent("last_sync.txt")

    guard FileManager.default.fileExists(atPath: timestampPath.path),
          let timestamp = try? String(contentsOf: timestampPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
          let date = ISO8601DateFormatter().date(from: timestamp) else {
      return nil
    }

    return date
  }

  func loadTasksFromGitHub(project: Project, token: String) async throws -> [DashboardTask] {
    guard let config = project.githubConfig else {
      throw StoreError.missingGitHubConfig
    }

    // Parse owner/repo from config.repo (format: "owner/repo")
    let parts = config.repo.split(separator: "/")
    guard parts.count == 2 else {
      throw StoreError.missingGitHubConfig
    }
    let owner = String(parts[0])
    let repo = String(parts[1])

    let service = GitHubService()
    let issues = try await service.listIssues(owner: owner, repo: repo, token: token, state: "all")

    var tasks: [DashboardTask] = []
    for issue in issues {
      let task = try mapGitHubIssueToTask(issue: issue, projectId: project.id)
      tasks.append(task)
    }

    return tasks
  }

  /// Save a task to GitHub Issues (create new or update existing).
  @discardableResult
  func saveTaskToGitHub(task: DashboardTask, project: Project, token: String) async throws -> DashboardTask {
    guard let config = project.githubConfig else {
      throw StoreError.missingGitHubConfig
    }

    // Parse owner/repo from config.repo (format: "owner/repo")
    let parts = config.repo.split(separator: "/")
    guard parts.count == 2 else {
      throw StoreError.missingGitHubConfig
    }
    let owner = String(parts[0])
    let repo = String(parts[1])

    let service = GitHubService()

    // Generate labels from task status and work state
    var labels: [String] = []
    labels.append("status:\(task.status.rawValue)")
    if let workState = task.workState {
      labels.append("work:\(workState.rawValue)")
    }
    if let syncLabels = config.labelFilter {
      labels.append(contentsOf: syncLabels)
    }

    // Format body with task metadata
    var bodyParts: [String] = []
    if let notes = task.notes, !notes.isEmpty {
      bodyParts.append(notes)
    }
    bodyParts.append("---")
    bodyParts.append("**Task ID:** `\(task.id)`")
    bodyParts.append("**Owner:** \(task.owner.rawValue)")
    bodyParts.append("**Created:** \(task.createdAt.formatted())")
    bodyParts.append("**Updated:** \(task.updatedAt.formatted())")
    let body = bodyParts.joined(separator: "\n")

    // Create or update based on githubIssueNumber
    let issue: GitHubIssue
    if let issueNumber = task.githubIssueNumber {
      // Update existing issue
      issue = try await service.updateIssue(
        owner: owner,
        repo: repo,
        token: token,
        issueNumber: issueNumber,
        title: task.title,
        body: body,
        state: task.status == .completed ? "closed" : "open",
        labels: labels
      )
    } else {
      // Create new issue
      issue = try await service.createIssue(
        owner: owner,
        repo: repo,
        token: token,
        title: task.title,
        body: body,
        labels: labels
      )
    }

    // Update task with GitHub issue number
    var updatedTask = task
    updatedTask.githubIssueNumber = issue.number
    return updatedTask
  }

  /// Map a cached GitHub issue to a DashboardTask.
  private func mapCachedIssueToTask(issue: CachedGitHubIssue, projectId: String, repo: String) throws -> DashboardTask {
    // Parse status from labels (e.g., "status:active", "status:completed")
    var status: TaskStatus = .active
    var workState: WorkState? = nil

    for label in issue.labels {
      let name = label.lowercased()
      if name.hasPrefix("status:") {
        let statusValue = String(name.dropFirst("status:".count))
        status = parseTaskStatus(statusValue)
      } else if name.hasPrefix("work:") {
        let workValue = String(name.dropFirst("work:".count))
        workState = parseWorkState(workValue)
      }
    }

    // Default: open issues are active, closed issues are completed
    if status == .active && issue.state == "closed" {
      status = .completed
    }

    // Parse owner from assignees (first assignee becomes owner)
    var owner: TaskOwner = .other("github")
    if let assignee = issue.assignees.first {
      owner = parseTaskOwner(assignee)
    }

    // Generate task ID from issue number
    let taskId = "github-\(repo.replacingOccurrences(of: "/", with: "-"))-\(issue.number)"

    return DashboardTask(
      id: taskId,
      title: issue.title,
      status: status,
      owner: owner,
      createdAt: Date(),  // We don't have createdAt in cache, use current time
      updatedAt: Date(),  // We don't have updatedAt in cache, use current time
      workState: workState,
      reviewState: nil,
      projectId: projectId,
      artifactPath: nil,
      notes: issue.body.isEmpty ? nil : issue.body,
      startedAt: nil,
      finishedAt: nil,
      sortOrder: nil,
      blockedBy: nil,
      pinned: nil,
      shape: nil,
      githubIssueNumber: issue.number
    )
  }

  /// Map a GitHub Issue to a DashboardTask.
  private func mapGitHubIssueToTask(issue: GitHubIssue, projectId: String) throws -> DashboardTask {
    // Parse status from labels (e.g., "status:active", "status:completed")
    var status: TaskStatus = .active
    var workState: WorkState? = nil

    for label in issue.labels ?? [] {
      let name = label.name.lowercased()
      if name.hasPrefix("status:") {
        let statusValue = String(name.dropFirst("status:".count))
        status = parseTaskStatus(statusValue)
      } else if name.hasPrefix("work:") {
        let workValue = String(name.dropFirst("work:".count))
        workState = parseWorkState(workValue)
      }
    }

    // Default: open issues are active, closed issues are completed
    if status == .active && issue.state == "closed" {
      status = .completed
    }

    // Parse owner from assignees (first assignee becomes owner)
    var owner: TaskOwner = .other("github")
    if let assignee = issue.assignees?.first {
      owner = parseTaskOwner(assignee.login)
    }

    return DashboardTask(
      id: "github-\(issue.number)",
      title: issue.title,
      status: status,
      owner: owner,
      createdAt: issue.createdAt,
      updatedAt: issue.updatedAt,
      workState: workState,
      reviewState: nil,
      projectId: projectId,
      artifactPath: nil,
      notes: issue.body,
      startedAt: nil,
      finishedAt: issue.closedAt,
      sortOrder: nil,
      blockedBy: nil,
      pinned: nil,
      shape: nil,
      githubIssueNumber: issue.number
    )
  }

  private func parseTaskStatus(_ value: String) -> TaskStatus {
    switch value {
    case "inbox": return .inbox
    case "active": return .active
    case "completed": return .completed
    case "rejected": return .rejected
    case "waiting_on", "waiting-on": return .waitingOn
    default: return .other(value)
    }
  }

  private func parseWorkState(_ value: String) -> WorkState {
    switch value {
    case "not_started", "not-started": return .notStarted
    case "in_progress", "in-progress": return .inProgress
    case "blocked": return .blocked
    default: return .other(value)
    }
  }

  private func parseTaskOwner(_ login: String) -> TaskOwner {
    switch login.lowercased() {
    case "lobs": return .lobs
    case "rafe", "rafesymonds": return .rafe
    default: return .other(login)
    }
  }

  func readArtifact(relativePath: String) throws -> String {
    let url = repoRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }

  func setStatus(taskId: String, status: TaskStatus) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.status = status
      task.updatedAt = Date()
      let out = try encodeToPythonJSON(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadLocalTasksFile()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].status = status
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setWorkState(taskId: String, workState: WorkState?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.workState = workState
      task.updatedAt = Date()
      let out = try encodeToPythonJSON(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadLocalTasksFile()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].workState = workState
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setReviewState(taskId: String, reviewState: ReviewState?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.reviewState = reviewState
      task.updatedAt = Date()
      let out = try encodeToPythonJSON(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadLocalTasksFile()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].reviewState = reviewState
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setSortOrder(taskId: String, sortOrder: Int?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.sortOrder = sortOrder
      task.updatedAt = Date()
      let out = try encodeToPythonJSON(task)
      try out.write(to: url, options: [.atomic])
      return
    }
  }

  func setTaskField(taskId: String, field: String, value: String?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
      if let value {
        dict[field] = value
      } else {
        dict.removeValue(forKey: field)
      }
      dict["updatedAt"] = ISO8601DateFormatter().string(from: Date())
      let out = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
      try out.write(to: url, options: [.atomic])
    }
  }

  func setTitleAndNotes(taskId: String, title: String, notes: String?) throws {
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.title = cleanTitle.isEmpty ? task.title : cleanTitle
      task.notes = (cleanNotes?.isEmpty == true) ? nil : cleanNotes
      task.updatedAt = Date()
      let out = try encodeToPythonJSON(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadLocalTasksFile()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    if !cleanTitle.isEmpty { file.tasks[idx].title = cleanTitle }
    file.tasks[idx].notes = (cleanNotes?.isEmpty == true) ? nil : cleanNotes
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func addTask(
    id: String = UUID().uuidString,
    title: String,
    owner: TaskOwner,
    status: TaskStatus,
    projectId: String? = nil,
    workState: WorkState? = .notStarted,
    reviewState: ReviewState? = .pending,
    notes: String?
  ) throws -> DashboardTask {
    let now = Date()
    let task = DashboardTask(
      id: id,
      title: title,
      status: status,
      owner: owner,
      createdAt: now,
      updatedAt: now,
      workState: workState,
      reviewState: reviewState,
      projectId: projectId,
      artifactPath: nil,
      notes: notes?.isEmpty == true ? nil : notes
    )

    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      try FileManager.default.createDirectory(at: tasksDirURL, withIntermediateDirectories: true)
      let out = try encodeToPythonJSON(task)
      try out.write(to: taskFileURL(taskId: task.id), options: [.atomic])
      return task
    }

    var file = try loadLocalTasksFile()
    file.tasks.append(task)
    try saveTasks(file)
    return task
  }

  func saveExistingTask(_ task: DashboardTask) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: task.id)
      let data = try encodeToPythonJSON(task)
      try data.write(to: url, options: [.atomic])
      return
    }

    var file = try loadLocalTasksFile()
    if let idx = file.tasks.firstIndex(where: { $0.id == task.id }) {
      file.tasks[idx] = task
    }
    try saveTasks(file)
  }

  func deleteTask(taskId: String) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      return
    }

    // Legacy mode: remove from tasks.json
    var file = try loadLocalTasksFile()
    file.tasks.removeAll { $0.id == taskId }
    try saveTasks(file)
  }

  func deleteResearchData(projectId: String) throws {
    let dir = researchDirURL.appendingPathComponent(projectId)
    if FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.removeItem(at: dir)
    }
  }

  func deleteTrackerData(projectId: String) throws {
    let dir = trackerDirURL.appendingPathComponent(projectId)
    if FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.removeItem(at: dir)
    }
  }

  func archiveTask(taskId: String) throws {
    // Per-file mode: move the task JSON into state/tasks-archive/
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let src = taskFileURL(taskId: taskId)
      if !FileManager.default.fileExists(atPath: src.path) { return }
      try FileManager.default.createDirectory(at: archiveDirURL, withIntermediateDirectories: true)
      let dst = archiveDirURL.appendingPathComponent("\(taskId).json")
      // Replace if exists
      _ = try? FileManager.default.removeItem(at: dst)
      try FileManager.default.moveItem(at: src, to: dst)
      return
    }

    // Legacy mode: remove from tasks.json
    var file = try loadLocalTasksFile()
    file.tasks.removeAll { $0.id == taskId }
    try saveTasks(file)
  }

  func archiveCompleted(olderThanDays days: Int) throws {
    guard days > 0 else { return }
    if !FileManager.default.fileExists(atPath: tasksDirURL.path) { return }

    let items = try FileManager.default.contentsOfDirectory(
      at: tasksDirURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))

    for url in items where url.pathExtension.lowercased() == "json" {
      let data = try Data(contentsOf: url)
      let t = try dec.decode(DashboardTask.self, from: data)
      if t.status.rawValue == "completed" && t.updatedAt < cutoff {
        try archiveTask(taskId: t.id)
      }
    }
  }

  func archiveReadInboxItems(olderThanDays days: Int, readItemIds: Set<String>) throws {
    guard days > 0 else { return }
    let fm = FileManager.default
    
    let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))
    
    // Archive from both inbox/ and artifacts/ directories
    let dirsToProcess: [(URL, URL)] = [
      (inboxDirURL, inboxArchiveDirURL),
      (artifactsDirURL, artifactsArchiveDirURL),
    ]
    
    for (sourceDir, archiveDir) in dirsToProcess {
      guard fm.fileExists(atPath: sourceDir.path) else { continue }
      
      let files = try fm.contentsOfDirectory(
        at: sourceDir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
      
      for fileURL in files {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "md" || ext == "txt" || ext == "markdown" else { continue }
        
        let filename = fileURL.lastPathComponent
        // Skip README files
        guard filename.lowercased() != "readme.md" else { continue }
        
        // Construct the item ID (matches InboxItem.id format)
        let dirName = sourceDir.lastPathComponent
        let itemId = "\(dirName)/\(filename)"
        
        // Check if item is read and old enough to archive
        guard readItemIds.contains(itemId) else { continue }
        
        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let modDate = (attrs[.modificationDate] as? Date) ?? Date()
        
        guard modDate < cutoff else { continue }
        
        // Archive the file
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let destURL = archiveDir.appendingPathComponent(filename)
        
        // Remove existing file at destination if present
        _ = try? fm.removeItem(at: destURL)
        
        // Move file to archive
        try fm.moveItem(at: fileURL, to: destURL)
      }
    }
  }

  // MARK: - Inbox (Design Docs)

  private var artifactsDirURL: URL { repoRoot.appendingPathComponent("artifacts") }
  private var inboxDirURL: URL { repoRoot.appendingPathComponent("inbox") }
  /// Repo-backed inbox (used by the orchestrator/monitor for JSON suggestions).
  private var inboxStateDirURL: URL {
    repoRoot.appendingPathComponent("state").appendingPathComponent("inbox")
  }
  private var inboxArchiveDirURL: URL { repoRoot.appendingPathComponent("inbox-archive") }
  private var artifactsArchiveDirURL: URL { repoRoot.appendingPathComponent("artifacts-archive") }
  private var inboxResponsesDirURL: URL {
    repoRoot.appendingPathComponent("state").appendingPathComponent("inbox-responses")
  }

  // MARK: - Inbox Read State (repo-backed)

  private var inboxReadStateURL: URL {
    repoRoot
      .appendingPathComponent("state")
      .appendingPathComponent("inbox")
      .appendingPathComponent("read-state.json")
  }

  func loadInboxReadState() throws -> InboxReadStateFile? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: inboxReadStateURL.path) else { return nil }
    let data = try Data(contentsOf: inboxReadStateURL)
    return try decoder().decode(InboxReadStateFile.self, from: data)
  }

  func saveInboxReadState(readItemIds: Set<String>, lastSeenThreadCounts: [String: Int]) throws {
    try FileManager.default.createDirectory(
      at: inboxReadStateURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )

    let file = InboxReadStateFile(
      schemaVersion: 1,
      generatedAt: Date(),
      readItemIds: Array(readItemIds).sorted(),
      lastSeenThreadCounts: lastSeenThreadCounts
    )

    let data = try encodeToPythonJSON(file)
    try data.write(to: inboxReadStateURL, options: [.atomic])
  }

  private var inboxThreadsDirURL: URL {
    inboxResponsesDirURL.appendingPathComponent("threads")
  }

  private func inboxThreadURL(docId: String) -> URL {
    // Use a hash-based filename to avoid collisions from naive sanitization.
    let digest = SHA256.hash(data: Data(docId.utf8))
    let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
    return inboxThreadsDirURL.appendingPathComponent(hex).appendingPathExtension("json")
  }

  func loadInboxItems() throws -> [InboxItem] {
    var items: [InboxItem] = []
    let fm = FileManager.default

    func parseSuggestionPreview(from data: Data, filename: String) -> (title: String, content: String, summary: String)? {
      // Suggestions are JSON files written by the orchestrator's Monitor to state/inbox/.
      // Expected shape is loosely:
      // { "type": "suggestion", "title": "…", "text"|"content"|"suggestion": "…", "summary": "…" }
      guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
        return nil
      }
      guard let dict = obj as? [String: Any] else { return nil }
      guard (dict["type"] as? String)?.lowercased() == "suggestion" else { return nil }

      let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let textCandidates: [String?] = [
        dict["content"] as? String,
        dict["text"] as? String,
        dict["suggestion"] as? String,
        dict["body"] as? String,
        dict["message"] as? String,
      ]
      let text = textCandidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first

      let prettyJSON: String = {
        if let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: pretty, encoding: .utf8) {
          return s
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
      }()

      let content = (text?.isEmpty == false) ? text! : prettyJSON
      let summary = ((dict["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
        ?? extractSummary(from: content)

      let finalTitle = (title?.isEmpty == false) ? title! : extractTitle(from: content, filename: filename)
      return (finalTitle, content, summary)
    }

    // Scan artifacts/, legacy inbox/, and repo-backed state/inbox/ (JSON suggestions).
    let dirs: [(URL, String)] = [
      (inboxDirURL, "inbox"),
      (artifactsDirURL, "artifacts"),
      (inboxStateDirURL, "state/inbox"),
    ]

    for (dir, prefix) in dirs {
      guard fm.fileExists(atPath: dir.path) else { continue }
      let files = try fm.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )

      for fileURL in files {
        let ext = fileURL.pathExtension.lowercased()
        let filename = fileURL.lastPathComponent

        // Skip README files + read state file.
        if filename.lowercased() == "readme.md" { continue }
        if filename.lowercased() == "read-state.json" { continue }

        // Supported inbox file types:
        // - Markdown/text documents (md/txt/markdown)
        // - JSON suggestions (type == "suggestion")
        let isTextDoc = (ext == "md" || ext == "txt" || ext == "markdown")
        let isJSON = (ext == "json")
        guard isTextDoc || isJSON else { continue }

        // Load only a small preview of the content to keep sync + navigation snappy.
        // Full content is loaded on-demand when the user selects an item.
        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let modDate = (attrs[.modificationDate] as? Date) ?? Date()
        let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0

        let maxPreviewBytes = 64 * 1024
        let previewData: Data = {
          if let handle = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? handle.close() }
            return handle.readData(ofLength: maxPreviewBytes)
          }
          return (try? Data(contentsOf: fileURL)) ?? Data()
        }()

        let previewString = String(data: previewData, encoding: .utf8)
          ?? String(decoding: previewData, as: UTF8.self)

        let isTruncated = fileSize > previewData.count

        // Derive title/summary from preview (good enough for list rendering)
        var title = extractTitle(from: previewString, filename: filename)
        var summary = extractSummary(from: previewString)
        var content = previewString

        if isJSON, let parsed = parseSuggestionPreview(from: previewData, filename: filename) {
          title = parsed.title
          content = parsed.content
          summary = parsed.summary
        } else if isJSON {
          // Only surface JSON files we understand (avoid polluting inbox with internal state).
          continue
        }

        let item = InboxItem(
          id: "\(prefix)/\(filename)",
          title: title,
          filename: filename,
          relativePath: "\(prefix)/\(filename)",
          content: content,
          contentIsTruncated: isTruncated,
          modifiedAt: modDate,
          isRead: false,
          summary: summary
        )
        items.append(item)
      }
    }

    // Sort by modification date, newest first
    items.sort { $0.modifiedAt > $1.modifiedAt }
    return items
  }

  func loadInboxResponses() throws -> [InboxResponse] {
    guard FileManager.default.fileExists(atPath: inboxResponsesDirURL.path) else { return [] }

    var out: [InboxResponse] = []
    let dec = decoder()

    guard let e = FileManager.default.enumerator(at: inboxResponsesDirURL, includingPropertiesForKeys: nil) else {
      return []
    }

    for case let url as URL in e {
      guard url.pathExtension.lowercased() == "json" else { continue }
      let data = try Data(contentsOf: url)
      // Skip files that are in the newer thread format (have messages array, no response field)
      if let r = try? dec.decode(InboxResponse.self, from: data) {
        out.append(r)
      }
    }

    out.sort { $0.updatedAt > $1.updatedAt }
    return out
  }

  func loadInboxResponse(docId: String) throws -> InboxResponse? {
    let url = inboxResponsesDirURL
      .appendingPathComponent(docId)
      .appendingPathExtension("json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder().decode(InboxResponse.self, from: data)
  }

  @discardableResult
  func saveInboxResponse(docId: String, response: String) throws -> InboxResponse {
    let now = Date()
    var existing = try loadInboxResponse(docId: docId)

    if existing == nil {
      existing = InboxResponse(
        id: UUID().uuidString,
        docId: docId,
        response: response,
        createdAt: now,
        updatedAt: now
      )
    } else {
      existing!.response = response
      existing!.updatedAt = now
    }

    let url = inboxResponsesDirURL
      .appendingPathComponent(docId)
      .appendingPathExtension("json")

    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )

    let data = try encodeToPythonJSON(existing!)
    try data.write(to: url, options: [.atomic])
    return existing!
  }

  // MARK: - Inbox Threads (threaded conversations)

  func loadInboxThread(docId: String) throws -> InboxThread? {
    let fm = FileManager.default

    // Preferred location (hash-based)
    let preferredURL = inboxThreadURL(docId: docId)
    if fm.fileExists(atPath: preferredURL.path) {
      let data = try Data(contentsOf: preferredURL)
      if let thread = try? decoder().decode(InboxThread.self, from: data) {
        return thread
      }
    }

    // Back-compat: previous thread storage used a naive safeId ("/" → "_") which can collide.
    let legacySafeId = docId.replacingOccurrences(of: "/", with: "_")
    let legacyThreadURL = inboxResponsesDirURL
      .appendingPathComponent(legacySafeId)
      .appendingPathExtension("json")
    if fm.fileExists(atPath: legacyThreadURL.path) {
      let data = try Data(contentsOf: legacyThreadURL)
      if let thread = try? decoder().decode(InboxThread.self, from: data) {
        // Migrate to preferred location
        try? saveInboxThread(thread)
        // Delete legacy file to prevent repeated migration
        try? FileManager.default.removeItem(at: legacyThreadURL)
        return thread
      }

      // Migrate legacy InboxResponse to thread format
      if let legacy = try? decoder().decode(InboxResponse.self, from: data),
         !legacy.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let msg = InboxThreadMessage(
          // Use a stable id so migration doesn't churn + cause rebase conflicts.
          id: legacy.id,
          author: "rafe",
          text: legacy.response,
          createdAt: legacy.createdAt
        )
        let thread = InboxThread(
          id: legacy.id,
          docId: legacy.docId,
          messages: [msg],
          createdAt: legacy.createdAt,
          updatedAt: legacy.updatedAt
        )
        try saveInboxThread(thread)
        // Delete legacy file to prevent repeated migration
        try? FileManager.default.removeItem(at: legacyThreadURL)
        return thread
      }
    }

    // Back-compat: legacy InboxResponse stored at path matching docId (may contain subdirs).
    if let legacy = try loadInboxResponse(docId: docId),
       !legacy.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let msg = InboxThreadMessage(
        // Use a stable id so migration doesn't churn + cause rebase conflicts.
        id: legacy.id,
        author: "rafe",
        text: legacy.response,
        createdAt: legacy.createdAt
      )
      let thread = InboxThread(
        id: legacy.id,
        docId: legacy.docId,
        messages: [msg],
        createdAt: legacy.createdAt,
        updatedAt: legacy.updatedAt
      )
      try saveInboxThread(thread)
      // Delete legacy file to prevent repeated migration
      let legacyURL = inboxResponsesDirURL
        .appendingPathComponent(docId)
        .appendingPathExtension("json")
      try? FileManager.default.removeItem(at: legacyURL)
      return thread
    }

    return nil
  }

  func loadAllInboxThreads() throws -> [String: InboxThread] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: inboxResponsesDirURL.path) else { return [:] }

    var result: [String: InboxThread] = [:]

    // 1) Load preferred (hash-based) threads first.
    if fm.fileExists(atPath: inboxThreadsDirURL.path),
       let e = fm.enumerator(at: inboxThreadsDirURL, includingPropertiesForKeys: nil) {
      for case let url as URL in e {
        guard url.pathExtension.lowercased() == "json" else { continue }
        let data = try Data(contentsOf: url)
        if let thread = try? decoder().decode(InboxThread.self, from: data) {
          result[thread.docId] = thread
        }
      }
    }

    // 2) Back-compat: scan remaining inbox-responses for legacy threads/responses and migrate.
    guard let e = fm.enumerator(at: inboxResponsesDirURL, includingPropertiesForKeys: nil) else {
      return result
    }

    for case let url as URL in e {
      // Skip preferred threads directory to avoid double-loading.
      if url.path.hasPrefix(inboxThreadsDirURL.path + "/") { continue }
      guard url.pathExtension.lowercased() == "json" else { continue }

      let data = try Data(contentsOf: url)

      // Thread format (legacy safeId).
      if let thread = try? decoder().decode(InboxThread.self, from: data) {
        // Only migrate if we *don't* already have a preferred thread.
        // Otherwise we'd keep rewriting the preferred file during every scan.
        if result[thread.docId] == nil {
          try? saveInboxThread(thread)
          result[thread.docId] = thread
          // Delete legacy file to prevent repeated migration
          try? FileManager.default.removeItem(at: url)
        }
        continue
      }

      // Legacy single-response format.
      if let legacy = try? decoder().decode(InboxResponse.self, from: data),
         !legacy.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        // If we already have a preferred thread for this docId, do NOT regenerate.
        // Regenerating creates a new UUID for the message and causes constant file churn.
        if result[legacy.docId] != nil { continue }

        let msg = InboxThreadMessage(
          // Use a stable id so migration doesn't churn + cause rebase conflicts.
          id: legacy.id,
          author: "rafe",
          text: legacy.response,
          createdAt: legacy.createdAt
        )
        let thread = InboxThread(
          id: legacy.id,
          docId: legacy.docId,
          messages: [msg],
          createdAt: legacy.createdAt,
          updatedAt: legacy.updatedAt
        )
        try? saveInboxThread(thread)
        result[thread.docId] = thread
        // Delete legacy file to prevent repeated migration
        try? FileManager.default.removeItem(at: url)
      }
    }

    return result
  }

  func saveInboxThread(_ thread: InboxThread) throws {
    let url = inboxThreadURL(docId: thread.docId)

    try FileManager.default.createDirectory(
      at: inboxThreadsDirURL,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let data = try encodeToPythonJSON(thread)
    try data.write(to: url, options: [.atomic])
  }

  private func extractTitle(from content: String, filename: String) -> String {
    // Look for first markdown heading
    for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("# ") {
        return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      }
    }
    // Fall back to filename without extension, prettified
    let base = (filename as NSString).deletingPathExtension
    return base.replacingOccurrences(of: "-", with: " ").capitalized
  }

  private func extractSummary(from content: String) -> String {
    // Skip headings, get first meaningful paragraph
    var lines: [String] = []
    var charCount = 0
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("#") { continue }
      if trimmed.isEmpty && lines.isEmpty { continue }
      if trimmed.isEmpty && !lines.isEmpty { break } // end of first paragraph
      lines.append(trimmed)
      charCount += trimmed.count
      if charCount > 200 { break }
    }
    let result = lines.joined(separator: " ")
    if result.count > 200 {
      return String(result.prefix(200)) + "…"
    }
    return result
  }

  // MARK: - Research Document (doc-based)

  private func researchDocURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("doc.md")
  }

  private func researchSourcesURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("sources.json")
  }

  /// Scan the `docs/` directory for research deliverable files.
  func loadResearchDeliverables(projectId: String) throws -> [ResearchDeliverable] {
    let docsDir = researchDirURL.appendingPathComponent(projectId).appendingPathComponent("docs")
    guard FileManager.default.fileExists(atPath: docsDir.path) else { return [] }

    let fm = FileManager.default
    let files = try fm.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
      .filter { $0.pathExtension == "md" }
      .sorted { a, b in
        let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        return da > db // newest first
      }

    return files.compactMap { url in
      let filename = url.lastPathComponent
      let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
      // Extract request ID from filename (format: <UUID-prefix>-<title>.md)
      let requestId = filename.contains("-") ? String(filename.prefix(8)) : nil
      // First line as title if it starts with #
      let title: String
      if let firstLine = content.split(separator: "\n", maxSplits: 1).first,
         firstLine.hasPrefix("# ") {
        title = String(firstLine.dropFirst(2))
      } else {
        title = filename.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: "-", with: " ")
      }
      return ResearchDeliverable(
        id: filename,
        filename: filename,
        title: title,
        requestIdPrefix: requestId,
        modifiedAt: modified,
        content: content
      )
    }
  }

  func loadResearchDoc(projectId: String) throws -> String {
    let url = researchDocURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: url.path) else { return "" }
    return try String(contentsOf: url, encoding: .utf8)
  }

  func saveResearchDoc(projectId: String, content: String) throws {
    let dir = researchDirURL.appendingPathComponent(projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = researchDocURL(projectId: projectId)
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  func saveResearchDeliverable(projectId: String, filename: String, content: String) throws {
    let docsDir = researchDirURL.appendingPathComponent(projectId).appendingPathComponent("docs")
    try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
    let url = docsDir.appendingPathComponent(filename)
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  func loadResearchSources(projectId: String) throws -> [ResearchSource] {
    let url = researchSourcesURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    let file = try decoder().decode(ResearchSourcesFile.self, from: data)
    return file.sources
  }

  func saveResearchSources(projectId: String, sources: [ResearchSource]) throws {
    let dir = researchDirURL.appendingPathComponent(projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = researchSourcesURL(projectId: projectId)
    let file = ResearchSourcesFile(sources: sources)
    let data = try encodeToPythonJSON(file)
    try data.write(to: url, options: [.atomic])
  }

  /// One-time migration: convert tiles to doc.md + sources.json.
  func migrateResearchTilesToDoc(projectId: String) throws {
    let tiles = try loadTiles(projectId: projectId)
    guard !tiles.isEmpty else { return }

    // Check if already migrated
    let docURL = researchDocURL(projectId: projectId)
    if FileManager.default.fileExists(atPath: docURL.path) { return }

    var markdown = ""
    var sources: [ResearchSource] = []

    // Group by type
    let findings = tiles.filter { $0.type == .finding }
    let notes = tiles.filter { $0.type == .note }
    let links = tiles.filter { $0.type == .link }
    let comparisons = tiles.filter { $0.type == .comparison }

    if !findings.isEmpty {
      markdown += "## Findings\n\n"
      for tile in findings {
        markdown += "### \(tile.title)\n\n"
        if let claim = tile.claim { markdown += "\(claim)\n\n" }
        if let evidence = tile.evidence, !evidence.isEmpty {
          markdown += "**Evidence:**\n"
          for e in evidence { markdown += "- \(e)\n" }
          markdown += "\n"
        }
        if let confidence = tile.confidence {
          markdown += "_Confidence: \(Int(confidence * 100))%_\n\n"
        }
      }
    }

    if !comparisons.isEmpty {
      markdown += "## Comparisons\n\n"
      for tile in comparisons {
        markdown += "### \(tile.title)\n\n"
        if let options = tile.options {
          for opt in options {
            markdown += "**\(opt.name)**\n"
            if let pros = opt.pros { for p in pros { markdown += "- ✅ \(p)\n" } }
            if let cons = opt.cons { for c in cons { markdown += "- ❌ \(c)\n" } }
            if let cost = opt.cost { markdown += "- 💰 Cost: \(cost)\n" }
            if let notes = opt.notes { markdown += "- 📝 \(notes)\n" }
            markdown += "\n"
          }
        }
      }
    }

    if !notes.isEmpty {
      markdown += "## Notes\n\n"
      for tile in notes {
        markdown += "### \(tile.title)\n\n"
        if let content = tile.content { markdown += "\(content)\n\n" }
      }
    }

    // Extract sources from link tiles
    for tile in links {
      if let url = tile.url {
        sources.append(ResearchSource(
          id: tile.id,
          url: url,
          title: tile.title,
          tags: tile.tags,
          addedAt: tile.createdAt
        ))
      }
      // Also add link summaries to doc
      if markdown.isEmpty || !links.isEmpty {
        if links.first?.id == tile.id { markdown += "## Sources\n\n" }
        markdown += "- [\(tile.title)](\(tile.url ?? ""))"
        if let summary = tile.summary { markdown += " — \(summary)" }
        markdown += "\n"
      }
    }

    try saveResearchDoc(projectId: projectId, content: markdown)
    if !sources.isEmpty {
      try saveResearchSources(projectId: projectId, sources: sources)
    }
  }

  // MARK: - Research Tiles (legacy)

  func loadTiles(projectId: String) throws -> [ResearchTile] {
    let dir = tilesDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var tiles: [ResearchTile] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let tile = try dec.decode(ResearchTile.self, from: data)
        tiles.append(tile)
      } catch {
        // Skip individual bad tiles instead of failing the entire load
        print("[LobsStore] Skipping tile \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    tiles.sort { $0.createdAt > $1.createdAt }
    return tiles
  }

  func saveTile(_ tile: ResearchTile) throws {
    let dir = tilesDirURL(projectId: tile.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(tile.id).json")
    let data = try encodeToPythonJSON(tile)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTile(projectId: String, tileId: String) throws {
    let url = tilesDirURL(projectId: projectId).appendingPathComponent("\(tileId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Research Requests

  func loadRequests(projectId: String) throws -> [ResearchRequest] {
    let dir = requestsDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var requests: [ResearchRequest] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        var req = try dec.decode(ResearchRequest.self, from: data)
        // Backfill projectId from directory context when missing from JSON
        if req.projectId == "unknown" {
          req.projectId = projectId
        }
        requests.append(req)
      } catch {
        print("[LobsStore] Skipping request \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    requests.sort { $0.createdAt > $1.createdAt }
    return requests
  }

  func saveRequest(_ request: ResearchRequest) throws {
    let dir = requestsDirURL(projectId: request.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(request.id).json")
    let data = try encodeToPythonJSON(request)
    try data.write(to: url, options: [.atomic])
  }

  func deleteRequest(projectId: String, requestId: String) throws {
    let url = requestsDirURL(projectId: projectId).appendingPathComponent("\(requestId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Tracker Items

  func loadTrackerItems(projectId: String) throws -> [TrackerItem] {
    let dir = trackerItemsDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var trackerItems: [TrackerItem] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let item = try dec.decode(TrackerItem.self, from: data)
        trackerItems.append(item)
      } catch {
        print("[LobsStore] Skipping tracker item \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    trackerItems.sort { $0.createdAt < $1.createdAt }
    return trackerItems
  }

  func saveTrackerItem(_ item: TrackerItem) throws {
    let dir = trackerItemsDirURL(projectId: item.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(item.id).json")
    let data = try encodeToPythonJSON(item)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTrackerItem(projectId: String, itemId: String) throws {
    let url = trackerItemsDirURL(projectId: projectId).appendingPathComponent("\(itemId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Tracker Requests

  private func trackerRequestsDirURL(projectId: String) -> URL {
    trackerDirURL.appendingPathComponent(projectId).appendingPathComponent("requests")
  }

  func loadTrackerRequests(projectId: String) throws -> [ResearchRequest] {
    let dir = trackerRequestsDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var requests: [ResearchRequest] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        var req = try dec.decode(ResearchRequest.self, from: data)
        if req.projectId == "unknown" {
          req.projectId = projectId
        }
        requests.append(req)
      } catch {
        print("[LobsStore] Skipping tracker request \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    requests.sort { $0.createdAt > $1.createdAt }
    return requests
  }

  func saveTrackerRequest(_ request: ResearchRequest) throws {
    let dir = trackerRequestsDirURL(projectId: request.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(request.id).json")
    let data = try encodeToPythonJSON(request)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTrackerRequest(projectId: String, requestId: String) throws {
    let url = trackerRequestsDirURL(projectId: projectId).appendingPathComponent("\(requestId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Task Templates

  private var templatesDirURL: URL {
    repoRoot.appendingPathComponent("state").appendingPathComponent("templates")
  }

  func loadTemplates() throws -> [TaskTemplate] {
    let dir = templatesDirURL
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var templates: [TaskTemplate] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let t = try dec.decode(TaskTemplate.self, from: data)
        templates.append(t)
      } catch {
        continue
      }
    }
    templates.sort { $0.name.lowercased() < $1.name.lowercased() }
    return templates
  }

  func saveTemplate(_ template: TaskTemplate) throws {
    try FileManager.default.createDirectory(at: templatesDirURL, withIntermediateDirectories: true)
    let url = templatesDirURL.appendingPathComponent("\(template.id).json")
    let data = try encodeToPythonJSON(template)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTemplate(id: String) throws {
    let url = templatesDirURL.appendingPathComponent("\(id).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Worker Status

  func loadWorkerStatus() throws -> WorkerStatus? {
    let url = repoRoot
      .appendingPathComponent("state")
      .appendingPathComponent("worker-status.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder().decode(WorkerStatus.self, from: data)
  }

  func loadWorkerHistory() throws -> WorkerHistory? {
    let url = repoRoot
      .appendingPathComponent("state")
      .appendingPathComponent("worker-history.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder().decode(WorkerHistory.self, from: data)
  }

  // MARK: - Main Session Usage

  func loadMainSessionUsage() throws -> MainSessionUsage? {
    // Tracked in the control repo by the orchestrator. The file name/path has changed a few times,
    // so we probe a small set of known locations for backwards/forwards compatibility.
    let candidates: [URL] = [
      repoRoot.appendingPathComponent("state").appendingPathComponent("main-session-usage.json"),
      repoRoot.appendingPathComponent("state").appendingPathComponent("main_session_usage.json"),
      repoRoot.appendingPathComponent("state").appendingPathComponent("main-usage.json"),
      repoRoot.appendingPathComponent("state").appendingPathComponent("ai-usage.json"),
      repoRoot.appendingPathComponent("state").appendingPathComponent("ai").appendingPathComponent("main-session-usage.json"),
      repoRoot.appendingPathComponent("state").appendingPathComponent("usage").appendingPathComponent("main-session-usage.json"),
      repoRoot.appendingPathComponent("state").appendingPathComponent("usage").appendingPathComponent("main_session_usage.json"),
    ]

    let fm = FileManager.default
    guard let url = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder().decode(MainSessionUsage.self, from: data)
  }

  // MARK: - Text Dumps

  private var textDumpsDir: URL {
    repoRoot.appendingPathComponent("state").appendingPathComponent("text-dumps")
  }

  func saveTextDump(_ dump: TextDump) throws {
    try FileManager.default.createDirectory(at: textDumpsDir, withIntermediateDirectories: true)
    let url = textDumpsDir.appendingPathComponent("\(dump.id).json")
    let data = try encodeToPythonJSON(dump)
    try data.write(to: url)
  }

  func loadTextDumps() throws -> [TextDump] {
    let dir = textDumpsDir
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    return try files
      .filter { $0.pathExtension == "json" }
      .map { try decoder().decode(TextDump.self, from: Data(contentsOf: $0)) }
      .sorted { $0.createdAt > $1.createdAt }
  }

  // MARK: - Project README

  private func projectReadmeURL(projectId: String) -> URL {
    repoRoot
      .appendingPathComponent("state")
      .appendingPathComponent("projects")
      .appendingPathComponent(projectId)
      .appendingPathComponent("README.md")
  }

  func loadProjectReadme(projectId: String) throws -> String? {
    let url = projectReadmeURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try String(contentsOf: url, encoding: .utf8)
  }

  func saveProjectReadme(projectId: String, content: String) throws {
    let url = projectReadmeURL(projectId: projectId)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      // Remove file if content is empty
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    } else {
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
  }

}