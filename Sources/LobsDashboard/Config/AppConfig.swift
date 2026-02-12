import Foundation

/// Application configuration model
/// Stored in ~/.lobs/config.json for local-only settings
struct AppConfig: Codable {
    /// DEPRECATED: Git URL for the control repository
    /// In API mode, state is managed by the server. This is kept for git UI features only.
    var controlRepoUrl: String
    
    /// DEPRECATED: Local filesystem path to the control repository
    /// In API mode, state is managed by the server. This is kept for git UI features only.
    var controlRepoPath: String
    
    /// Whether the user has completed initial onboarding
    var onboardingComplete: Bool
    
    /// URL of the lobs-server API (default: http://localhost:8000)
    /// This is the PRIMARY configuration for state management
    var serverURL: String
    
    /// User preferences and UI state
    var settings: UserSettings
    
    init(
        controlRepoUrl: String = "",
        controlRepoPath: String = "",
        onboardingComplete: Bool = false,
        serverURL: String = "http://localhost:8000",
        settings: UserSettings = UserSettings()
    ) {
        self.controlRepoUrl = controlRepoUrl
        self.controlRepoPath = controlRepoPath
        self.onboardingComplete = onboardingComplete
        self.serverURL = serverURL
        self.settings = settings
    }
}
