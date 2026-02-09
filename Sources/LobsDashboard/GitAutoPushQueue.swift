import Foundation

/// Batches many "auto-push" requests into a single commit + push.
///
/// Motivation: UI actions can trigger many small saves in quick succession (typing, toggles, etc.).
/// Pushing each one immediately is noisy and slower than bundling changes.
///
/// Behavior:
/// - First enqueue starts a debounce window (default: 10s).
/// - Additional enqueues during the window are folded into the same batch.
/// - At flush time we: pull --rebase, git add -A, commit once (if needed), then push.
/// - Errors are surfaced via the owning `AppViewModel`'s `lastPushError`.
actor GitAutoPushQueue {
  private weak var owner: AppViewModel?

  private var pendingRepoURL: URL?
  private var pendingMessages: [String] = []
  private var flushTask: Task<Void, Never>?
  private var isFlushing: Bool = false

  /// How long to wait after the first change before committing/pushing.
  private let debounceNanoseconds: UInt64

  init(owner: AppViewModel, debounceSeconds: TimeInterval = 10.0) {
    self.owner = owner
    self.debounceNanoseconds = UInt64(debounceSeconds * 1_000_000_000)
  }

  func enqueue(repoURL: URL, message: String) {
    // If repo changes, flush the existing batch ASAP and start a new one.
    if let current = pendingRepoURL, current != repoURL {
      // Fire-and-forget; we don't want callers blocked.
      Task { await self.flushNow() }
      pendingRepoURL = repoURL
      pendingMessages = [message]
      scheduleFlushIfNeeded()
      return
    }

    pendingRepoURL = repoURL
    pendingMessages.append(message)
    scheduleFlushIfNeeded()
  }

  func flushNow() async {
    flushTask?.cancel()
    flushTask = nil
    await flushIfNeeded()
  }

  private func scheduleFlushIfNeeded() {
    guard flushTask == nil else { return }

    flushTask = Task {
      do {
        try await Task.sleep(nanoseconds: debounceNanoseconds)
      } catch {
        // Cancelled.
        return
      }
      await flushIfNeeded()
    }
  }

  private func flushIfNeeded() async {
    guard !isFlushing else { return }
    guard let repoURL = pendingRepoURL else { return }
    guard !pendingMessages.isEmpty else { return }

    isFlushing = true
    flushTask = nil

    let messages = pendingMessages
    pendingMessages = []
    pendingRepoURL = nil

    defer { isFlushing = false }

    let commitMessage = Self.bundleCommitMessage(from: messages)

    // Pull first to reduce conflicts.
    await MainActor.run {
      self.owner?.lastPushAttemptAt = Date()
    }

    let pull = await Git.runWithRetry(["pull", "--rebase"], cwd: repoURL, maxRetries: 2)
    if !pull.success {
      let msg = pull.error?.errorDescription ?? "Pull --rebase failed"
      await MainActor.run {
        self.owner?.lastPushError = msg
      }
      return
    }

    let addResult = await Git.runAsyncWithErrorHandling(["add", "-A"], cwd: repoURL)
    if !addResult.success {
      let msg = addResult.error?.errorDescription ?? "Failed to stage changes"
      await MainActor.run {
        self.owner?.lastPushError = msg
      }
      return
    }

    // No staged changes → nothing to do.
    let stagedClean = await Git.runAsyncWithErrorHandling(["diff", "--cached", "--quiet"], cwd: repoURL)
    if stagedClean.success {
      return
    }

    let author = "Lobs <thelobsbot@gmail.com>"
    let committerEnv: [String: String] = [
      "GIT_COMMITTER_NAME": "Lobs",
      "GIT_COMMITTER_EMAIL": "thelobsbot@gmail.com",
    ]

    let commit = await Git.runAsyncWithErrorHandling([
      "commit", "--author", author, "-m", commitMessage,
    ], cwd: repoURL, env: committerEnv)

    if !commit.success {
      let msg = commit.error?.errorDescription ?? "Commit failed"
      await MainActor.run {
        self.owner?.lastPushError = msg
      }
      return
    }

    let push = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
    if !push.success {
      // If suggested, pull --rebase and retry.
      if push.suggestsPull {
        let repull = await Git.runWithRetry(["pull", "--rebase"], cwd: repoURL, maxRetries: 2)
        if !repull.success {
          let msg = repull.error?.errorDescription ?? "Pull failed"
          await MainActor.run {
            self.owner?.lastPushError = msg
          }
          return
        }

        let retry = await Git.runAsyncWithErrorHandling(["push"], cwd: repoURL)
        if !retry.success {
          let msg = retry.error?.errorDescription ?? "Push failed"
          await MainActor.run {
            self.owner?.lastPushError = msg
          }
          return
        }
      } else {
        let msg = push.error?.errorDescription ?? "Push failed"
        await MainActor.run {
          self.owner?.lastPushError = msg
        }
        return
      }
    }

    // Get current commit hash for display.
    let hashResult = await Git.runAsyncWithErrorHandling(["rev-parse", "--short", "HEAD"], cwd: repoURL)
    let commitHash = hashResult.success ? hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil

    await MainActor.run {
      self.owner?.lastSuccessfulPushAt = Date()
      self.owner?.lastPushedCommitHash = commitHash
      self.owner?.lastPushError = nil
    }
  }

  private static func bundleCommitMessage(from messages: [String]) -> String {
    guard !messages.isEmpty else { return "Lobs: bundled updates" }
    if messages.count == 1 { return messages[0] }

    let head = messages.prefix(3)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let suffixCount = max(0, messages.count - head.count)
    let summary = head.joined(separator: "; ")

    if suffixCount > 0 {
      return "Lobs: bundled updates (\(messages.count) changes): \(summary); +\(suffixCount) more"
    }

    return "Lobs: bundled updates (\(messages.count) changes): \(summary)"
  }
}
