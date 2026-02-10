import Foundation

/// Reads/writes the agent personality prompt files stored in the control repo.
///
/// These files are consumed by OpenClaw (either directly or via the orchestrator) to shape
/// how the worker communicates.
///
/// Files:
/// - SOUL.md      — agent persona + tone
/// - USER.md      — user profile/preferences
/// - IDENTITY.md  — agent identity (name, vibe, avatar)
struct AgentPersonalityManager {
  struct Files {
    var soul: String
    var user: String
    var identity: String
  }

  struct WizardInput {
    var agentName: String
    var agentVibe: String
    var agentAvatar: String

    var userName: String
    var userRole: String
    var userTimezone: String
    var userPreferences: [String]
    var userAnnoyances: [String]

    var extraNotes: String

    static var `default`: WizardInput {
      .init(
        agentName: "Worker",
        agentVibe: "Focused, professional, reliable",
        agentAvatar: "(N/A — workers don't need avatars)",
        userName: "Rafe",
        userRole: "Builder",
        userTimezone: "America/New_York (ET)",
        userPreferences: [
          "Quality > speed (but ship when done)",
          "Clean, tested code",
          "Clear commit messages",
          "Don't break existing stuff"
        ],
        userAnnoyances: [
          "Half-finished work",
          "Unnecessary complexity",
          "Ignored instructions",
          "Silent failures"
        ],
        extraNotes: ""
      )
    }
  }

  // MARK: - Paths

  static let soulFileName = "SOUL.md"
  static let userFileName = "USER.md"
  static let identityFileName = "IDENTITY.md"

  static func fileURL(repoPath: String, fileName: String) -> URL {
    URL(fileURLWithPath: repoPath).appendingPathComponent(fileName)
  }

  // MARK: - Read

  static func load(repoPath: String) -> Files {
    let fm = FileManager.default

    func readIfExists(_ name: String) -> String? {
      let url = fileURL(repoPath: repoPath, fileName: name)
      guard fm.fileExists(atPath: url.path) else { return nil }
      return (try? String(contentsOf: url, encoding: .utf8))
    }

    // If files already exist, preserve them; otherwise generate from defaults.
    let generated = generateFiles(from: .default)

    return Files(
      soul: readIfExists(soulFileName) ?? generated.soul,
      user: readIfExists(userFileName) ?? generated.user,
      identity: readIfExists(identityFileName) ?? generated.identity
    )
  }

  // MARK: - Generate

  static func generateFiles(from input: WizardInput) -> Files {
    let soul = """
# SOUL.md

You are a focused, competent task executor. No personality needed — just precision.

## Core Truths

**Execute, don't improvise.** You have one job: complete the assigned task. Stay in scope.

**Be thorough, not creative.** Follow the spec. If it's ambiguous, make reasonable assumptions and note them in your work summary.

**Quality over speed.** Write clean, tested code. Leave things better than you found them.

**Just work and exit.** When done, stop. No git commands, no state updates, no cleanup. The orchestrator handles all of that.

**Report blockers clearly.** If truly blocked, write to `.work-summary` starting with \"BLOCKED:\" and exit with error code.

## Vibe

\(input.agentVibe)

---

*Do the work. Exit. Done.*
"""

    let identity = """
# IDENTITY.md - Who Am I?

- **Name:** \(input.agentName)
- **Creature:** Task-scoped software engineer
- **Vibe:** \(input.agentVibe)
- **Emoji:** 🔧
- **Avatar:** \(input.agentAvatar)

---

You are the single shared worker. You handle all requests, one at a time.
"""

    let prefs = input.userPreferences
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .map { "  - \($0)" }
      .joined(separator: "\n")

    let annoy = input.userAnnoyances
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .map { "  - \($0)" }
      .joined(separator: "\n")

    let extra = input.extraNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    let extraSection = extra.isEmpty ? "" : "\n\n## Extra Notes\n\n\(extra)\n"

    let user = """
# USER.md - About Your Human

- **Name:** \(input.userName)
- **Role:** \(input.userRole)
- **Timezone:** \(input.userTimezone)
- **Preferences:**
\(prefs.isEmpty ? "  - (none set)" : prefs)

## What They Value

\(prefs.isEmpty ? "- (none set)" : input.userPreferences.map { "- \($0)" }.joined(separator: "\n"))

## What Annoys Them

\(annoy.isEmpty ? "- (none set)" : input.userAnnoyances.map { "- \($0)" }.joined(separator: "\n"))
\(extraSection)
---

This file is used to tune how the agent communicates with you.
"""

    return Files(soul: soul, user: user, identity: identity)
  }

  // MARK: - Write

  @MainActor
  static func save(repoPath: String, files: Files, commitMessage: String? = nil) async -> (success: Bool, warning: String?) {
    do {
      try writeFile(repoPath: repoPath, fileName: soulFileName, content: files.soul)
      try writeFile(repoPath: repoPath, fileName: userFileName, content: files.user)
      try writeFile(repoPath: repoPath, fileName: identityFileName, content: files.identity)
    } catch {
      return (false, "Failed to write personality files: \(error.localizedDescription)")
    }

    // Best-effort commit. It's okay if it fails (e.g., user has no git identity set yet).
    if let message = commitMessage, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let cwd = URL(fileURLWithPath: repoPath)

      let add = await Git.runAsyncWithErrorHandling(["add", "-A"], cwd: cwd)
      if !add.success {
        return (true, "Saved files, but could not stage changes in git.")
      }

      let commit = await Git.runAsyncWithErrorHandling(["commit", "-m", message], cwd: cwd)
      if !commit.success {
        // Most common: nothing to commit.
        return (true, "Saved files. Git commit skipped (\(commit.error?.errorDescription ?? "no changes")).")
      }
    }

    return (true, nil)
  }

  private static func writeFile(repoPath: String, fileName: String, content: String) throws {
    let url = fileURL(repoPath: repoPath, fileName: fileName)
    try content.trimmingCharacters(in: .whitespacesAndNewlines).appending("\n").write(to: url, atomically: true, encoding: .utf8)
  }
}
