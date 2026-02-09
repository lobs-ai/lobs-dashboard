import Foundation

/// Application configuration model
/// Stored in ~/.lobs/config.json for local-only settings
struct AppConfig: Codable {
    /// Git URL for the control repository (e.g., "git@github.com:user/lobs-control.git")
    var controlRepoUrl: String
    
    /// Local filesystem path to the control repository (e.g., "/Users/them/lobs-control")
    var controlRepoPath: String
    
    /// Whether the user has completed initial onboarding
    var onboardingComplete: Bool
    
    /// User preferences and UI state
    var settings: UserSettings
    
    init(
        controlRepoUrl: String = "",
        controlRepoPath: String = "",
        onboardingComplete: Bool = false,
        settings: UserSettings = UserSettings()
    ) {
        self.controlRepoUrl = controlRepoUrl
        self.controlRepoPath = controlRepoPath
        self.onboardingComplete = onboardingComplete
        self.settings = settings
    }
}
