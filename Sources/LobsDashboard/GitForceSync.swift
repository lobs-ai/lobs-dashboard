import Foundation

/// Manual git overrides for when automatic sync/push fails.
///
/// These operations are intentionally explicit and guarded:
/// - Force Pull stashes first (if needed) then hard-resets to origin/main.
/// - Force Push tries --force-with-lease, and only escalates to --force after confirmation.
extension AppViewModel {
  // MARK: - Manual Force Sync

  /// Force-pull remote state for the control repo, discarding local changes.
  ///
  /// Safety: if there are any local changes (including untracked files), we stash them first.
  ///
  /// Steps:
  /// - stash local changes (safety backup)
  /// - git fetch origin
  /// - git reset --hard origin/main
  /// - git clean -fd
  /// - reload from disk
  func forcePullDiscardLocal() {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    lastError = nil

    Task { @MainActor in
      let now = Date()
      let iso = ISO8601DateFormatter().string(from: now)

      // Check for local changes (tracked or untracked).
      let status = await Git.runAsyncWithErrorHandling(["status", "--porcelain"], cwd: repoURL)
      if !status.success {
        await MainActor.run {
          self.flashError(status.error?.errorDescription ?? "Failed to check git status")
          self.isGitBusy = false
        }
        return
      }

      let hasLocalChanges = !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      var didStash = false
      var stashMessage: String? = nil

      if hasLocalChanges {
        stashMessage = "dashboard-sync-backup (force-pull) \(iso)"
        let stash = await Git.runAsyncWithErrorHandling(["stash", "push", "-u", "-m", stashMessage!], cwd: repoURL)
        if !stash.success {
          await MainActor.run {
            self.flashError(stash.error?.errorDescription ?? "Failed to stash local changes")
            self.isGitBusy = false
          }
          self.logForceGitOperation("FORCE_PULL stash FAILED: \(stash.error?.technicalMessage ?? "unknown")")
          return
        }
        didStash = true
      }

      self.logForceGitOperation("FORCE_PULL start\(didStash ? " (stashed)" : "")")

      let fetch = await Git.runAsyncWithErrorHandling(["fetch", "origin"], cwd: repoURL)
      if !fetch.success {
        await MainActor.run {
          self.flashError(fetch.error?.errorDescription ?? "Fetch failed")
          self.isGitBusy = false
        }
        self.logForceGitOperation("FORCE_PULL fetch FAILED: \(fetch.error?.technicalMessage ?? "unknown")")
        return
      }

      let reset = await Git.runAsyncWithErrorHandling(["reset", "--hard", "origin/main"], cwd: repoURL)
      if !reset.success {
        await MainActor.run {
          self.flashError(reset.error?.errorDescription ?? "Reset failed")
          self.isGitBusy = false
        }
        self.logForceGitOperation("FORCE_PULL reset FAILED: \(reset.error?.technicalMessage ?? "unknown")")
        return
      }

      let clean = await Git.runAsyncWithErrorHandling(["clean", "-fd"], cwd: repoURL)
      if !clean.success {
        // Best-effort; still attempt to reload.
        self.logForceGitOperation("FORCE_PULL clean FAILED: \(clean.error?.technicalMessage ?? "unknown")")
      }

      await MainActor.run {
        self.isGitBusy = false
        if didStash {
          self.flashSuccess("Local changes saved to stash. Synced to remote version.")
        } else {
          self.flashSuccess("Synced to remote version.")
        }
        self.reload()
      }

      self.logForceGitOperation("FORCE_PULL complete\(didStash ? " (stash: \(stashMessage ?? ""))" : "")")
    }
  }

  /// Force-push local state to origin, overwriting remote if necessary.
  ///
  /// Safety:
  /// - Always attempts --force-with-lease first.
  /// - If that fails, sets `forcePushEscalationPresented` so the UI can request
  ///   explicit confirmation before using --force.
  func forcePushOverwriteRemote() {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    forcePushEscalationPresented = false
    forcePushEscalationError = nil

    Task { @MainActor in
      await MainActor.run {
        self.lastPushAttemptAt = Date()
      }

      self.logForceGitOperation("FORCE_PUSH start (--force-with-lease)")

      let push = await Git.runAsyncWithErrorHandling(["push", "--force-with-lease"], cwd: repoURL)
      if push.success {
        let hashResult = await Git.runAsyncWithErrorHandling(["rev-parse", "--short", "HEAD"], cwd: repoURL)
        let commitHash = hashResult.success ? hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        await MainActor.run {
          self.lastSuccessfulPushAt = Date()
          self.lastPushedCommitHash = commitHash
          self.lastPushError = nil
          self.flashSuccess("Force pushed (with lease)")
          self.isGitBusy = false
        }

        self.logForceGitOperation("FORCE_PUSH complete (--force-with-lease)")
        return
      }

      // Lease-protected force push failed. Prompt for escalation to --force.
      let err = push.error?.errorDescription ?? "Force push (with lease) failed"
      await MainActor.run {
        self.lastPushError = err
        self.forcePushEscalationError = err
        self.forcePushEscalationPresented = true
        self.isGitBusy = false
      }
      self.logForceGitOperation("FORCE_PUSH failed (--force-with-lease): \(push.error?.technicalMessage ?? "unknown")")
    }
  }

  /// Final escalation: `git push --force`. Call only after explicit user confirmation.
  func forcePushOverwriteRemoteForce() {
    guard let repoURL else {
      flashError("Repo path not set")
      return
    }
    guard !isGitBusy else { return }

    isGitBusy = true
    forcePushEscalationPresented = false

    Task { @MainActor in
      await MainActor.run {
        self.lastPushAttemptAt = Date()
      }

      self.logForceGitOperation("FORCE_PUSH start (--force)")

      let push = await Git.runAsyncWithErrorHandling(["push", "--force"], cwd: repoURL)
      if !push.success {
        let err = push.error?.errorDescription ?? "Force push failed"
        await MainActor.run {
          self.lastPushError = err
          self.flashError(err)
          self.isGitBusy = false
        }
        self.logForceGitOperation("FORCE_PUSH failed (--force): \(push.error?.technicalMessage ?? "unknown")")
        return
      }

      let hashResult = await Git.runAsyncWithErrorHandling(["rev-parse", "--short", "HEAD"], cwd: repoURL)
      let commitHash = hashResult.success ? hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil

      await MainActor.run {
        self.lastSuccessfulPushAt = Date()
        self.lastPushedCommitHash = commitHash
        self.lastPushError = nil
        self.flashSuccess("Force pushed (overwrote remote)")
        self.isGitBusy = false
      }

      self.logForceGitOperation("FORCE_PUSH complete (--force)")
    }
  }

  // MARK: - Logging

  /// Append an audit line to ~/.openclaw/logs/git-force.log
  fileprivate func logForceGitOperation(_ message: String) {
    let fm = FileManager.default
    let logsDir = fm.homeDirectoryForCurrentUser
      .appendingPathComponent(".openclaw")
      .appendingPathComponent("logs")
    let logURL = logsDir.appendingPathComponent("git-force.log")

    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"

    do {
      try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

      if fm.fileExists(atPath: logURL.path) {
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        if let data = line.data(using: .utf8) {
          try handle.write(contentsOf: data)
        }
        try handle.close()
      } else {
        try line.write(to: logURL, atomically: true, encoding: .utf8)
      }
    } catch {
      // Avoid surfacing logging issues to the user.
      print("[git-force-log] failed: \(error)")
    }
  }
}
