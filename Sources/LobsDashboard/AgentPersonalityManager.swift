import Foundation

/// Agent personality manager using lobs-server API endpoints.
/// Uses /api/agents/{agent_type}/files/{filename} to read/write personality files.
///
/// Files (stored on server):
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

  // MARK: - Paths (DISABLED - file-based access removed)

  static let soulFileName = "SOUL.md"
  static let userFileName = "USER.md"
  static let identityFileName = "IDENTITY.md"

  // MARK: - Read from API

  @MainActor
  static func load(api: APIService, agentType: String = "worker") async throws -> Files {
    async let soul = api.loadAgentFile(agentType: agentType, filename: soulFileName)
    async let user = api.loadAgentFile(agentType: agentType, filename: userFileName)
    async let identity = api.loadAgentFile(agentType: agentType, filename: identityFileName)
    
    let (soulContent, userContent, identityContent) = try await (soul, user, identity)
    
    return Files(
      soul: soulContent ?? "",
      user: userContent ?? "",
      identity: identityContent ?? ""
    )
  }
  
  // Legacy synchronous version (returns defaults)
  static func load() -> Files {
    return generateFiles(from: .default)
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

  // MARK: - Write to API

  @MainActor
  static func save(files: Files, api: APIService, agentType: String = "worker", commitMessage: String? = nil) async -> (success: Bool, warning: String?) {
    do {
      try await api.saveAgentFile(agentType: agentType, filename: soulFileName, content: files.soul)
      try await api.saveAgentFile(agentType: agentType, filename: userFileName, content: files.user)
      try await api.saveAgentFile(agentType: agentType, filename: identityFileName, content: files.identity)
      return (true, nil)
    } catch {
      return (false, "Failed to save personality files: \(error.localizedDescription)")
    }
  }
  
  // Legacy version without API (returns error)
  @MainActor
  static func save(files: Files, commitMessage: String? = nil) async -> (success: Bool, warning: String?) {
    return (false, "API instance required for saving personality files")
  }
}
