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
      let store = LobsControlStore(repoRoot: repoURL)
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
    setSelectedStatus(.completed, autoPush: autoPush)
  }

  func rejectSelected(autoPush: Bool) {
    setSelectedStatus(.rejected, autoPush: autoPush)
  }

  func submitTaskToLobs(title: String, notes: String?, autoPush: Bool) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty, let repoURL else { return }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      let task = try store.addTask(
        title: trimmedTitle,
        owner: .lobs,
        status: .inbox,
        notes: trimmedNotes
      )

      _ = try Git.run(["add", "-A"], cwd: repoURL)

      let stagedClean = try Git.run(["diff", "--cached", "--quiet"], cwd: repoURL)
      if stagedClean.exitCode == 0 {
        reload()
        return
      }

      let msg = "Lobs: submit task \(task.id)"
      let commit = try Git.run([
        "commit",
        "--author", "Lobs <thelobsbot@gmail.com>",
        "-m", msg
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

      reload()

    } catch {
      lastError = String(describing: error)
    }
  }

  private func setSelectedStatus(_ status: TaskStatus, autoPush: Bool) {
    guard let repoURL, let id = selectedTaskId else { return }

    do {
      let store = LobsControlStore(repoRoot: repoURL)
      try store.setStatus(taskId: id, status: status)

      // Git commit (dashboard-generated = Lobs)
      _ = try Git.run(["add", "-A"], cwd: repoURL)

      // Skip commit/push when no changes staged.
      let stagedClean = try Git.run(["diff", "--cached", "--quiet"], cwd: repoURL)
      if stagedClean.exitCode == 0 {
        reload()
        return
      }

      let msg = "Lobs: set \(id) status=\(status.rawValue)"
      let commit = try Git.run([
        "commit",
        "--author", "Lobs <thelobsbot@gmail.com>",
        "-m", msg
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
