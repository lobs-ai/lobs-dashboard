import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
  private let settings = UserDefaults.standard
  private let repoPathKey = "repoPath"

  @Published private(set) var repoPath: String = ""

  @Published var tasks: [DashboardTask] = []
  @Published var selectedTaskId: String? = nil
  @Published var artifactText: String = "(select a task)"
  @Published var lastError: String? = nil

  /// Transient error banner — shown briefly then auto-dismissed.
  @Published var errorBanner: String? = nil

  /// Whether a background git operation is in flight.
  @Published var isGitBusy: Bool = false

  // Kanban UX
  @Published var searchText: String = ""
  @Published var ownerFilter: String = "all"
  @Published var wipLimitActive: Int = 6

  // Completed hygiene
  @Published var completedShowRecent: Int = 30
  @Published var autoArchiveCompleted: Bool = false
  @Published var archiveCompletedAfterDays: Int = 30

  // Popover state for task detail
  @Published var popoverTaskId: String? = nil

  init() {
    repoPath = settings.string(forKey: repoPathKey) ?? ""
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

    do {
      try syncRepo(repoURL: repoURL)

      let store = LobsControlStore(repoRoot: repoURL)

      if autoArchiveCompleted {
        try store.archiveCompleted(olderThanDays: archiveCompletedAfterDays)
      }

      let file = try store.loadTasks()
      tasks = file.tasks
      lastError = nil
      try loadArtifactForSelected(store: store)

    } catch {
      lastError = String(describing: error)
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
        let t = tasks[idx]
        try store.setStatus(taskId: t.id, status: t.status)
        if let rs = t.reviewState {
          try store.setReviewState(taskId: t.id, reviewState: rs)
        }
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
        flashError("Git sync failed: \(error.localizedDescription)")
        // Reload from disk to get true state.
        reload()
      }
      isGitBusy = false
    }
  }

  // MARK: - Actions (now optimistic + async)

  func approveSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: { $0.reviewState = .approved }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set \(id) reviewState=approved",
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
    optimisticUpdate(taskId: id, localMutation: { $0.reviewState = .rejected }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set \(id) reviewState=rejected",
        autoPush: autoPush
      )
    }
  }

  func completeSelected(autoPush: Bool) {
    guard let id = selectedTaskId else { return }
    optimisticUpdate(taskId: id, localMutation: { $0.status = .completed }) { repoURL in
      try await self.asyncCommitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set \(id) status=completed",
        autoPush: autoPush
      )
    }
  }

  func submitTaskToLobs(title: String, notes: String?, autoPush: Bool) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty, let repoURL else { return }

    // Optimistically add to local list.
    let now = Date()
    let newTask = DashboardTask(
      id: UUID().uuidString,
      title: trimmedTitle,
      status: .inbox,
      owner: .lobs,
      createdAt: now,
      updatedAt: now,
      workState: .notStarted,
      reviewState: .pending,
      artifactPath: nil,
      notes: trimmedNotes
    )

    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      tasks.append(newTask)
    }

    // Write to disk + async git.
    do {
      let store = LobsControlStore(repoRoot: repoURL)
      _ = try store.addTask(
        title: trimmedTitle,
        owner: .lobs,
        status: .inbox,
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
        flashError("Git push failed: \(error.localizedDescription)")
        reload()
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
        throw NSError(domain: "Git", code: Int(push.exitCode),
                      userInfo: [NSLocalizedDescriptionKey: push.stderr])
      }
    }
  }

  private func syncRepo(repoURL: URL) throws {
    let remotes = try Git.run(["remote"], cwd: repoURL)
    if remotes.exitCode != 0 { return }
    let hasOrigin = remotes.stdout.split(separator: "\n").map(String.init).contains("origin")
    if !hasOrigin { return }

    _ = try Git.run(["fetch", "origin"], cwd: repoURL)
    _ = try Git.run(["reset", "--hard", "origin/main"], cwd: repoURL)
    _ = try Git.run(["clean", "-fd"], cwd: repoURL)
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
        throw NSError(domain: "Git", code: Int(push.exitCode),
                      userInfo: [NSLocalizedDescriptionKey: push.stderr])
      }
    }
  }

  // Drag-and-drop support
  @Published var draggingTaskId: String? = nil

  var filteredTasks: [DashboardTask] {
    var out = tasks

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
      .init(title: "Inbox", dropStatus: .inbox) { $0.status == .inbox },
      .init(title: "Active", dropStatus: .active) { $0.status == .active },
      .init(title: "Waiting on", dropStatus: .waitingOn) { $0.status == .waitingOn },
      .init(title: "Completed", dropStatus: .completed) { $0.status == .completed },
      .init(title: "Rejected", dropStatus: .rejected) { $0.status == .rejected },
      .init(title: "Other", dropStatus: .other("inbox")) {
        switch $0.status {
        case .inbox, .active, .waitingOn, .completed, .rejected:
          return false
        case .other:
          return true
        }
      },
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
}
