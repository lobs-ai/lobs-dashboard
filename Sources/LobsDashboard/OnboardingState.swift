import Foundation

/// Persistent, resumable onboarding state.
///
/// Stored at: ~/.lobs/.onboarding-state.json
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
  case prereqs
  case workspace
  case cloneCoreRepos
  case installOpenClaw
  case configureOpenClaw
  case agentSetup
  case startOrchestrator
  case done
}

enum OnboardingStateManager {
  private static let configDirectory: URL = {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".lobs")
  }()

  static let stateFile: URL = {
    configDirectory.appendingPathComponent(".onboarding-state.json")
  }()

  static func load() -> OnboardingState {
    if FileManager.default.fileExists(atPath: stateFile.path) {
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
      try data.write(to: stateFile, options: .atomic)
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
