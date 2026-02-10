import SwiftUI

struct OnboardingCloneCoreReposView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let workspacePath: String
  let controlRepoUrl: String
  let isNewControlRepo: Bool
  let onComplete: (URL) -> Void

  @State private var isRunning: Bool = false
  @State private var isFinished: Bool = false
  @State private var steps: [Step] = []
  @State private var errorMessage: String? = nil
  @State private var canRetry: Bool = false

  // Existing-repo choice UI
  @State private var pendingDecision: PendingDecision? = nil

  struct Step: Identifiable {
    let id = UUID()
    var title: String
    var status: Status

    enum Status: Equatable {
      case pending
      case inProgress
      case completed
      case warning(String)
      case error(String)

      var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
      }

      var color: Color {
        switch self {
        case .pending: return .secondary.opacity(0.5)
        case .inProgress: return .blue
        case .completed: return .green
        case .warning: return .orange
        case .error: return .red
        }
      }
    }
  }

  enum ExistingRepoAction {
    case skip
    case pullLatest
    case reclone
  }

  struct PendingDecision: Identifiable {
    let id = UUID()
    let repoName: String
    let repoPath: URL
    let continuation: CheckedContinuation<ExistingRepoAction, Never>
  }

  private let orchestratorRepoUrl = "git@github.com:RafeSymonds/lobs-orchestrator.git"
  private let workspaceRepoUrl = "git@github.com:RafeSymonds/lobs-workspace.git"

  private var controlPath: URL { URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-control") }
  private var orchestratorPath: URL { URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-orchestrator") }
  private var lobsWorkspacePath: URL { URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-workspace") }

  // MARK: - View

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Text("Clone Core Repos")
          .font(.system(size: 28, weight: .semibold))
        Text("We’ll set up Lobs’ local workspace and clone the repos it needs.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 16) {
        ForEach(steps) { step in
          HStack(spacing: 12) {
            Image(systemName: step.status.icon)
              .font(.system(size: 14))
              .foregroundColor(step.status.color)
              .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
              Text(step.title)
                .font(.system(size: 14))

              switch step.status {
              case .warning(let msg):
                Text(msg).font(.system(size: 12)).foregroundColor(.orange)
              case .error(let msg):
                Text(msg).font(.system(size: 12)).foregroundColor(.red)
              default:
                EmptyView()
              }
            }

            Spacer()

            if case .inProgress = step.status {
              ProgressView().scaleEffect(0.7)
            }
          }
        }
      }
      .frame(width: 560)
      .padding(20)
      .background(Theme.cardBg)
      .cornerRadius(12)
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

      if let errorMessage {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
          Text(errorMessage)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }
        .frame(maxWidth: 560, alignment: .leading)
      }

      Spacer()

      HStack(spacing: 12) {
        if canRetry {
          Button(action: start) {
            Text("Try Again")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.white)
              .frame(width: 140)
              .padding(.vertical, 10)
          }
          .buttonStyle(.plain)
          .background(Theme.accent)
          .cornerRadius(8)
        } else {
          Button(action: start) {
            Text(isRunning ? "Working…" : (isFinished ? "Re-run" : "Start"))
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.white)
              .frame(width: 140)
              .padding(.vertical, 10)
          }
          .buttonStyle(.plain)
          .background(Theme.accent)
          .cornerRadius(8)
          .disabled(isRunning)
        }

        if isFinished {
          Text(canContinue ? "Ready — use Next" : "Fix required errors above")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
      }
      .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      wizard.configureNext(title: "Next", enabled: isFinished && canContinue) {
        completeIfPossible()
      }
      wizard.configureSkip(shown: false)

      if steps.isEmpty {
        steps = [
          Step(title: "Clone lobs-control", status: .pending),
          Step(title: "Validate lobs-control structure", status: .pending),
          Step(title: "Clone lobs-orchestrator", status: .pending),
          Step(title: "Clone lobs-workspace", status: .pending)
        ]
      }
    }
    .onChange(of: readyToProceed) { ok in
      wizard.updateNextEnabled(ok)
    }
    .confirmationDialog(
      pendingDecision?.repoName ?? "Repository exists",
      isPresented: Binding(
        get: { pendingDecision != nil },
        set: { if !$0 { pendingDecision = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Skip") {
        pendingDecision?.continuation.resume(returning: .skip)
        pendingDecision = nil
      }
      Button("Pull latest") {
        pendingDecision?.continuation.resume(returning: .pullLatest)
        pendingDecision = nil
      }
      Button("Re-clone") {
        pendingDecision?.continuation.resume(returning: .reclone)
        pendingDecision = nil
      }
      Button("Cancel", role: .cancel) {
        pendingDecision?.continuation.resume(returning: .skip)
        pendingDecision = nil
      }
    } message: {
      if let p = pendingDecision {
        Text("\(p.repoPath.path) already exists. What do you want to do?")
      }
    }
  }

  private var readyToProceed: Bool { isFinished && canContinue }

  private var canContinue: Bool {
    // Require control repo clone + validation to proceed; other repos may fail.
    guard steps.indices.contains(0), steps.indices.contains(1) else { return false }
    if case .error = steps[0].status { return false }
    if case .error = steps[1].status { return false }
    return true
  }

  // MARK: - Actions

  private func start() {
    isRunning = true
    isFinished = false
    errorMessage = nil
    canRetry = false

    // Reset step statuses.
    for idx in steps.indices {
      steps[idx].status = .pending
    }

    Task {
      await runAll()
    }
  }

  private func completeIfPossible() {
    guard canContinue else { return }
    onComplete(controlPath)
  }

  private func runAll() async {
    // Clone all repos in parallel for speed.
    await updateStep(0, .inProgress)
    await updateStep(2, .inProgress)
    await updateStep(3, .inProgress)

    async let controlRes = ensureCloned(repoName: "lobs-control", url: controlRepoUrl, dest: controlPath)
    async let orchRes = ensureCloned(repoName: "lobs-orchestrator", url: orchestratorRepoUrl, dest: orchestratorPath)
    async let wsRes = ensureCloned(repoName: "lobs-workspace", url: workspaceRepoUrl, dest: lobsWorkspacePath)

    let controlOK = await controlRes
    let orchOK = await orchRes
    let wsOK = await wsRes

    // If a step already has a warning (e.g., "Exists, skipped"), preserve it.
    await MainActor.run {
      if controlOK {
        if case .inProgress = steps[0].status { steps[0].status = .completed }
      }
      if orchOK {
        if case .inProgress = steps[2].status { steps[2].status = .completed }
      }
      if wsOK {
        if case .inProgress = steps[3].status { steps[3].status = .completed }
      }

      if !controlOK, case .inProgress = steps[0].status { steps[0].status = .error("Clone failed") }
      if !orchOK, case .inProgress = steps[2].status { steps[2].status = .error("Clone failed") }
      if !wsOK, case .inProgress = steps[3].status { steps[3].status = .error("Clone failed") }
    }

    // Validate structure (depends on control repo).
    if controlOK {
      await updateStep(1, .inProgress)
      let validateOK = await validateControlStructure(at: controlPath)
      if validateOK {
        // validateControlStructure may set warning text; don't override.
        await MainActor.run {
          if case .inProgress = steps[1].status {
            steps[1].status = .completed
          }
        }
      }
    } else {
      await updateStep(1, .error("Cannot validate until lobs-control is cloned"))
    }

    await MainActor.run {
      isRunning = false
      isFinished = true
      canRetry = steps.contains(where: { if case .error = $0.status { return true } else { return false } })

      if !canContinue {
        errorMessage = errorMessage ?? "Some required steps failed. Fix the errors above, then try again."
      }
    }
  }

  // MARK: - Git ops

  private func ensureCloned(repoName: String, url: String, dest: URL) async -> Bool {
    let fm = FileManager.default

    // Existing folder handling.
    if fm.fileExists(atPath: dest.path) {
      let gitDir = dest.appendingPathComponent(".git")
      if fm.fileExists(atPath: gitDir.path) {
        let action = await askExistingRepoAction(repoName: repoName, repoPath: dest)
        switch action {
        case .skip:
          await updateStepWarning(forRepo: repoName, msg: "Exists, skipped")
          return true
        case .pullLatest:
          let pull = await Shell.envAsync("git", ["pull", "--rebase"], cwd: dest)
          if pull.ok {
            await updateStepWarning(forRepo: repoName, msg: "Pulled latest")
            return true
          }
          await updateStepError(forRepo: repoName, message: formatGitFailureMessage(pull, hint: hintForAuthOrNetwork(pull)))
          return false
        case .reclone:
          do {
            let backup = dest.deletingLastPathComponent().appendingPathComponent("\(dest.lastPathComponent).backup-\(Int(Date().timeIntervalSince1970))")
            try fm.moveItem(at: dest, to: backup)
            await updateStepWarning(forRepo: repoName, msg: "Moved existing to \(backup.lastPathComponent)")
          } catch {
            await updateStepError(forRepo: repoName, message: "Failed to move existing folder: \(error.localizedDescription)")
            return false
          }
          // Fallthrough to clone.
        }
      } else {
        await updateStepError(forRepo: repoName, message: "Folder exists but is not a git repo: \(dest.path)")
        return false
      }
    }

    let res = await Shell.envAsync("git", ["clone", url, dest.path])
    if !res.ok {
      await updateStepError(forRepo: repoName, message: formatGitFailureMessage(res, hint: hintForAuthOrNetwork(res)))
      return false
    }

    return true
  }

  private func validateControlStructure(at repoRoot: URL) async -> Bool {
    let fm = FileManager.default
    var created: [String] = []

    let requiredDirs = [
      "state",
      "state/tasks",
      "inbox",
      "artifacts"
    ]

    for d in requiredDirs {
      let p = repoRoot.appendingPathComponent(d)
      if !fm.fileExists(atPath: p.path) {
        do {
          try fm.createDirectory(at: p, withIntermediateDirectories: true)
          created.append(d + "/")
        } catch {
          await updateStepError(index: 1, message: "Failed to create \(d): \(error.localizedDescription)")
          await finishWithError("Failed to create \(d): \(error.localizedDescription)")
          return false
        }
      }
    }

    let requiredFiles: [(rel: String, content: String)] = [
      ("state/projects.json", """
      {
        \"schemaVersion\": 1,
        \"projects\": []
      }
      """),
      (".gitignore", ".DS_Store\n*~\n.*.swp\n")
    ]

    for f in requiredFiles {
      let p = repoRoot.appendingPathComponent(f.rel)
      if !fm.fileExists(atPath: p.path) {
        do {
          try f.content.write(to: p, atomically: true, encoding: .utf8)
          created.append(f.rel)
        } catch {
          await updateStepError(index: 1, message: "Failed to create \(f.rel): \(error.localizedDescription)")
          await finishWithError("Failed to create \(f.rel): \(error.localizedDescription)")
          return false
        }
      }
    }

    if !created.isEmpty {
      // Best-effort commit.
      _ = await Shell.envAsync("git", ["add", "-A"], cwd: repoRoot)
      _ = await Shell.envAsync("git", ["commit", "-m", "Initialize lobs-control structure"], cwd: repoRoot)
      await updateStep(1, .warning("Created: \(created.joined(separator: ", "))"))
    }

    return true
  }

  // MARK: - Existing repo prompt

  private func askExistingRepoAction(repoName: String, repoPath: URL) async -> ExistingRepoAction {
    await withCheckedContinuation { cont in
      Task { @MainActor in
        pendingDecision = PendingDecision(repoName: repoName, repoPath: repoPath, continuation: cont)
      }
    }
  }

  // MARK: - Step updates

  private func updateStepWarning(forRepo repoName: String, msg: String) async {
    if repoName == "lobs-control" {
      await updateStep(0, .warning(msg))
    } else if repoName == "lobs-orchestrator" {
      await updateStep(2, .warning(msg))
    } else if repoName == "lobs-workspace" {
      await updateStep(3, .warning(msg))
    }
  }

  private func updateStepError(forRepo repoName: String, message: String) async {
    if repoName == "lobs-control" {
      await updateStep(0, .error(message))
    } else if repoName == "lobs-orchestrator" {
      await updateStep(2, .error(message))
    } else if repoName == "lobs-workspace" {
      await updateStep(3, .error(message))
    }

    await finishWithError(message)
  }

  private func updateStepError(index: Int, message: String) async {
    await updateStep(index, .error(message))
  }

  private func updateStep(_ index: Int, _ status: Step.Status) async {
    await MainActor.run {
      guard steps.indices.contains(index) else { return }
      steps[index].status = status
    }
  }

  private func finishWithError(_ message: String) async {
    await MainActor.run {
      errorMessage = message
      isRunning = false
      canRetry = true
    }
  }

  // MARK: - Error formatting

  private func formatGitFailureMessage(_ res: Shell.Result, hint: String?) -> String {
    let raw = (res.stderr.isEmpty ? res.stdout : res.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
    if let hint, !hint.isEmpty {
      return raw.isEmpty ? hint : (raw + "\n\n" + hint)
    }
    return raw.isEmpty ? "git failed." : raw
  }

  private func hintForAuthOrNetwork(_ res: Shell.Result) -> String? {
    let s = (res.stderr + "\n" + res.stdout).lowercased()
    if s.contains("permission denied") || s.contains("publickey") || s.contains("authentication failed") {
      return "Auth failure. Try running: gh auth login"
    }
    if s.contains("could not resolve host") || s.contains("network is unreachable") || s.contains("timed out") {
      return "Network error. Check your connection and try again."
    }
    return nil
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

#Preview {
  OnboardingCloneCoreReposView(
    workspacePath: NSHomeDirectory() + "/lobs",
    controlRepoUrl: "git@github.com:user/lobs-control.git",
    isNewControlRepo: false,
    onComplete: { _ in }
  )
  .environmentObject(OnboardingWizardContext())
  .frame(width: 800, height: 600)
}
