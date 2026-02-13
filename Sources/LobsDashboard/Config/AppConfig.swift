import Foundation

/// Application configuration model
/// Stored in ~/.lobs/config.json for local-only settings
struct AppConfig: Codable {
    /// Whether the user has completed initial onboarding
    var onboardingComplete: Bool
    
    /// URL of the lobs-server API (default: http://localhost:8000)
    /// This is the PRIMARY configuration for state management
    var serverURL: String

    /// Legacy git config retained for compatibility with fallback workflows.
    var controlRepoUrl: String?
    var controlRepoPath: String?
    
    /// User preferences and UI state
    var settings: UserSettings
    
    init(
        onboardingComplete: Bool = false,
        serverURL: String = "http://localhost:8000",
        controlRepoUrl: String? = nil,
        controlRepoPath: String? = nil,
        settings: UserSettings = UserSettings()
    ) {
        self.onboardingComplete = onboardingComplete
        self.serverURL = serverURL
        self.controlRepoUrl = controlRepoUrl
        self.controlRepoPath = controlRepoPath
        self.settings = settings
    }
}
