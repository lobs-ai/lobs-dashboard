import Foundation

/// Persistent, resumable onboarding state.
///
/// Stored at: ~/lobs/.onboarding-state.json (primary)
/// and also written into the chosen workspace as: <workspace>/.onboarding-state.json
struct OnboardingState: Codable, Equatable {
  var completedSteps: [String]
  var workspace: String?
  var agentName: String?
  var userName: String?

  init(
    completedSteps: [String] = [],
    workspace: String? = nil,
    agentName: String? = nil,
    userName: String? = nil
  ) {
    self.completedSteps = completedSteps
    self.workspace = workspace
    self.agentName = agentName
    self.userName = userName
  }

  func isCompleted(_ step: OnboardingStepID) -> Bool {
    completedSteps.contains(step.rawValue)
  }

  mutating func markCompleted(_ step: OnboardingStepID) {
    if !completedSteps.contains(step.rawValue) {
      completedSteps.append(step.rawValue)
    }
  }
}

enum OnboardingStepID: String, CaseIterable {
  case welcome
  case prereqs  // Legacy, kept for compatibility
  case workspace
  case installOpenClaw  // Legacy
  case configureOpenClaw  // Legacy
  case agentSetup  // Legacy
  case startOrchestrator  // Legacy
  case firstProject  // Legacy
  case serverGuide
  case done
}

enum OnboardingStateManager {
  private static var configDirectory: URL { LobsPaths.appSupport }

  static var stateFile: URL { LobsPaths.onboardingState }

  private static func workspaceStateFile(workspacePath: String) -> URL {
    URL(fileURLWithPath: workspacePath).appendingPathComponent(".onboarding-state.json")
  }

  static func load(preferredWorkspacePath: String? = nil) -> OnboardingState {
    let fm = FileManager.default

    // Prefer the workspace-local state file if we know the workspace.
    if let ws = preferredWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !ws.isEmpty {
      let wsFile = workspaceStateFile(workspacePath: ws)
      if fm.fileExists(atPath: wsFile.path) {
        do {
          let data = try Data(contentsOf: wsFile)
          return try JSONDecoder().decode(OnboardingState.self, from: data)
        } catch {
          print("⚠️ Failed to load onboarding state from workspace: \(error)")
        }
      }
    }

    // Fallback to config directory state.
    if fm.fileExists(atPath: stateFile.path) {
      do {
        let data = try Data(contentsOf: stateFile)
        return try JSONDecoder().decode(OnboardingState.self, from: data)
      } catch {
        print("⚠️ Failed to load onboarding state: \(error)")
      }
    }

    return OnboardingState()
  }

  static func save(_ state: OnboardingState) {
    do {
      if !FileManager.default.fileExists(atPath: configDirectory.path) {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      var data = try encoder.encode(state)
      // Match ConfigManager formatting (Python-friendly spacing).
      if var jsonString = String(data: data, encoding: .utf8) {
        jsonString = jsonString.replacingOccurrences(of: " : ", with: ": ")
        data = Data(jsonString.utf8)
      }

      // Always write primary.
      try data.write(to: stateFile, options: .atomic)

      // Also write into the workspace when known.
      if let ws = state.workspace?.trimmingCharacters(in: .whitespacesAndNewlines), !ws.isEmpty {
        let wsFile = workspaceStateFile(workspacePath: ws)
        _ = try? FileManager.default.createDirectory(at: wsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: wsFile, options: .atomic)
      }
    } catch {
      print("⚠️ Failed to save onboarding state: \(error)")
    }
  }

  static func reset() {
    do {
      if FileManager.default.fileExists(atPath: stateFile.path) {
        try FileManager.default.removeItem(at: stateFile)
      }
    } catch {
      print("⚠️ Failed to reset onboarding state: \(error)")
    }
  }
}
