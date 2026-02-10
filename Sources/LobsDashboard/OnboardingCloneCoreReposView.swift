import SwiftUI

struct OnboardingCloneCoreReposView: View {
  let workspacePath: String
  let controlRepoUrl: String
  let isNewControlRepo: Bool
  let onBack: () -> Void
  let onComplete: (URL) -> Void

  @State private var isRunning: Bool = false
  @State private var steps: [Step] = []
  @State private var errorMessage: String? = nil
  @State private var canRetry: Bool = false

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

  private var controlPath: URL { URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-control") }
  private var orchestratorPath: URL { URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-orchestrator") }
  private var lobsWorkspacePath: URL { URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-workspace") }

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
        Button(action: onBack) {
          Text("Back")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .disabled(isRunning && !canRetry)

        if canRetry {
          Button(action: start) {
            Text("Try Again")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.white)
              .frame(width: 120)
              .padding(.vertical, 10)
          }
          .buttonStyle(.plain)
          .background(Theme.accent)
          .cornerRadius(8)
        } else {
          Button(action: start) {
            Text(isRunning ? "Working…" : "Start")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.white)
              .frame(width: 120)
              .padding(.vertical, 10)
          }
          .buttonStyle(.plain)
          .background(Theme.accent)
          .cornerRadius(8)
          .disabled(isRunning)
        }
      }
      .padding(.bottom, 60)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      if steps.isEmpty {
        steps = [
          Step(title: "Clone lobs-control", status: .pending),
          Step(title: "Validate lobs-control structure", status: .pending),
          Step(title: "Clone lobs-orchestrator", status: .pending),
          Step(title: "Clone lobs-workspace", status: .pending)
        ]
      }
    }
  }

  private func start() {
    isRunning = true
    errorMessage = nil
    canRetry = false

    Task {
      await runAll()
    }
  }

  private func runAll() async {
    // 1) lobs-control
    await updateStep(0, .inProgress)
    let controlCloneOK = await ensureCloned(url: controlRepoUrl, dest: controlPath)
    if !controlCloneOK { return }
    await updateStep(0, .completed)

    // 2) validate structure
    await updateStep(1, .inProgress)
    let validateOK = await validateControlStructure(at: controlPath)
    if !validateOK { return }
    await updateStep(1, .completed)

    // 3) orchestrator
    await updateStep(2, .inProgress)
    let orchOK = await ensureCloned(url: "https://github.com/RafeSymonds/lobs-orchestrator.git", dest: orchestratorPath)
    if !orchOK { return }
    await updateStep(2, .completed)

    // 4) lobs-workspace
    await updateStep(3, .inProgress)
    let wsOK = await ensureCloned(url: "https://github.com/RafeSymonds/lobs-workspace.git", dest: lobsWorkspacePath)
    if !wsOK { return }
    await updateStep(3, .completed)

    await MainActor.run {
      isRunning = false
      onComplete(controlPath)
    }
  }

  private func ensureCloned(url: String, dest: URL) async -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: dest.path) {
      // If it's already a git repo, keep going.
      let gitDir = dest.appendingPathComponent(".git")
      if fm.fileExists(atPath: gitDir.path) {
        await updateCurrentStepWarning("Exists, using current checkout")
        return true
      }
      await finishWithError("Folder exists but is not a git repo: \(dest.path)")
      return false
    }

    let res = await Shell.envAsync("git", ["clone", url, dest.path])
    if !res.ok {
      await finishWithError("git clone failed for \(url): \(res.stderr.isEmpty ? res.stdout : res.stderr)")
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

  private func updateCurrentStepWarning(_ msg: String) async {
    // Apply to the last in-progress step.
    await MainActor.run {
      if let idx = steps.firstIndex(where: { if case .inProgress = $0.status { return true } else { return false } }) {
        steps[idx].status = .warning(msg)
      }
    }
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

      if let idx = steps.firstIndex(where: { if case .inProgress = $0.status { return true } else { return false } }) {
        steps[idx].status = .error(message)
      }
    }
  }
}

#Preview {
  OnboardingCloneCoreReposView(
    workspacePath: NSHomeDirectory() + "/lobs",
    controlRepoUrl: "git@github.com:user/lobs-control.git",
    isNewControlRepo: false,
    onBack: {},
    onComplete: { _ in }
  )
  .frame(width: 800, height: 600)
}
