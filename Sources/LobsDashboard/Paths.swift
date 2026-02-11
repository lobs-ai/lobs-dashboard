import Foundation

/// Centralized path configuration to avoid TCC prompts.
/// Using ~/Library/Application Support/Lobs instead of ~/lobs
/// because Application Support is not TCC-protected.
enum LobsPaths {
  /// Base directory for all Lobs data.
  /// ~/Library/Application Support/Lobs
  static var appSupport: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Lobs")
  }
  
  /// Default workspace path as a string.
  static var defaultWorkspace: String {
    appSupport.path
  }
  
  /// Config file location (config.json).
  static var configFile: URL {
    appSupport.appendingPathComponent("config.json")
  }
  
  /// Onboarding state file.
  static var onboardingState: URL {
    appSupport.appendingPathComponent("onboarding-state.json")
  }
  
  /// Dashboard build commit file.
  static var buildCommit: URL {
    appSupport.appendingPathComponent("dashboard-build-commit")
  }
  
  /// Ensure the app support directory exists.
  static func ensureAppSupportExists() throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: appSupport.path) {
      try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }
  }
}
