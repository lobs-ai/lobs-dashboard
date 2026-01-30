import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
  @AppStorage("repoPath") private var repoPath: String = ""

  @Published var tasks: [DashboardTask] = []
  @Published var selectedTaskId: String? = nil
  @Published var artifactText: String = "(select a task)"
  @Published var lastError: String? = nil

  var repoURL: URL? {
    guard !repoPath.isEmpty else { return nil }
    return URL(fileURLWithPath: repoPath)
  }

  func setRepoURL(_ url: URL) {
    repoPath = url.path
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

      if let id = selectedTaskId, let t = tasks.first(where: { $0.id == id }), let ap = t.artifactPath {
        artifactText = try store.readArtifact(relativePath: ap)
      } else {
        artifactText = "(select a task)"
      }

    } catch {
      lastError = String(describing: error)
    }
  }

  func selectTask(_ task: DashboardTask) {
    selectedTaskId = task.id
    reload()
  }

  func approveSelected(autoPush: Bool) {
    setSelectedStatus(.completed, autoPush: autoPush)
  }

  func rejectSelected(autoPush: Bool) {
    setSelectedStatus(.rejected, autoPush: autoPush)
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
}
