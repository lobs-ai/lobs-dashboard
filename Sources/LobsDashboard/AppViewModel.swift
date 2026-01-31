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

  // Kanban UX
  @Published var searchText: String = ""
  @Published var ownerFilter: String = "all" // "all" | "lobs" | "rafe" | "other"
  @Published var wipLimitActive: Int = 6

  // Completed hygiene
  @Published var completedShowRecent: Int = 30
  @Published var autoArchiveCompleted: Bool = false
  @Published var archiveCompletedAfterDays: Int = 30

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
      // Always sync with remote first so the dashboard operates on the latest state.
      try syncRepo(repoURL: repoURL)

      let store = LobsControlStore(repoRoot: repoURL)

      // Optional hygiene: archive old completed tasks.
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
    loadArtifactForSelected()
  }

  func approveSelected(autoPush: Bool) {
    setSelectedReviewState(.approved, autoPush: autoPush)
  }

  func requestChangesSelected(autoPush: Bool) {
    setSelectedReviewState(.changesRequested, autoPush: autoPush)
  }

  func rejectSelected(autoPush: Bool) {
    // Reject = reject the artifact/review.
    setSelectedReviewState(.rejected, autoPush: autoPush)
  }

  func completeSelected(autoPush: Bool) {
    setSelectedStatus(.completed, autoPush: autoPush)
  }

  func submitTaskToLobs(title: String, notes: String?, autoPush: Bool) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty, let repoURL else { return }

    do {
      // Pull before making any changes.
      try syncRepo(repoURL: repoURL)

      let store = LobsControlStore(repoRoot: repoURL)
      let task = try store.addTask(
        title: trimmedTitle,
        owner: .lobs,
        status: .inbox,
        notes: trimmedNotes
      )

      try commitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: submit task \(task.id)",
        autoPush: autoPush
      )

      reload()

    } catch {
      lastError = String(describing: error)
    }
  }

  private func syncRepo(repoURL: URL) throws {
    // "Easy mode" sync:
    // - no rebase
    // - tolerate force-pushes
    // - always operate on origin/main

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

    // Skip commit/push when no changes staged.
    let stagedClean = try Git.run(["diff", "--cached", "--quiet"], cwd: repoURL)
    if stagedClean.exitCode == 0 {
      return
    }

    // Use a GitHub noreply-style email so commits do not get attributed to your personal account.
    let author = "Lobs <thelobsbot@gmail.com>"

    let commit = try Git.run([
      "commit",
      "--author", author,
      "-m", message
    ], cwd: repoURL)

    if commit.exitCode != 0 {
      throw NSError(domain: "Git", code: Int(commit.exitCode), userInfo: [NSLocalizedDescriptionKey: commit.stderr])
    }

    if autoPush {
      let push = try Git.run(["push"], cwd: repoURL)
      if push.exitCode != 0 {
        throw NSError(domain: "Git", code: Int(push.exitCode), userInfo: [NSLocalizedDescriptionKey: push.stderr])
      }
    }
  }

  private func setSelectedStatus(_ status: TaskStatus, autoPush: Bool) {
    guard let repoURL, let id = selectedTaskId else { return }

    do {
      // Pull (sync) before making any changes.
      try syncRepo(repoURL: repoURL)

      let store = LobsControlStore(repoRoot: repoURL)
      try store.setStatus(taskId: id, status: status)

      try commitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set \(id) status=\(status.rawValue)",
        autoPush: autoPush
      )

      reload()

    } catch {
      lastError = String(describing: error)
    }
  }

  private func setSelectedReviewState(_ reviewState: ReviewState, autoPush: Bool) {
    guard let repoURL, let id = selectedTaskId else { return }

    do {
      // Pull (sync) before making any changes.
      try syncRepo(repoURL: repoURL)

      let store = LobsControlStore(repoRoot: repoURL)
      try store.setReviewState(taskId: id, reviewState: reviewState)

      try commitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: set \(id) reviewState=\(reviewState.rawValue)",
        autoPush: autoPush
      )

      reload()

    } catch {
      lastError = String(describing: error)
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

  func moveTask(taskId: String, to status: TaskStatus) {
    guard let repoURL else { return }
    do {
      // Pull (sync) before making any changes.
      try syncRepo(repoURL: repoURL)

      let store = LobsControlStore(repoRoot: repoURL)
      try store.setStatus(taskId: taskId, status: status)
      try commitAndMaybePush(
        repoURL: repoURL,
        message: "Lobs: move \(taskId) to \(status.rawValue)",
        autoPush: true
      )
      reload()
    } catch {
      lastError = String(describing: error)
    }
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
}
