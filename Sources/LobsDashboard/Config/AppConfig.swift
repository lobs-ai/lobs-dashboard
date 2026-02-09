import Foundation

/// Application configuration model
struct AppConfig: Codable {
    /// Git URL for the control repository (e.g., "git@github.com:user/lobs-control.git")
    var controlRepoUrl: String
    
    /// Local filesystem path to the control repository (e.g., "/Users/them/lobs-control")
    var controlRepoPath: String
    
    /// Whether the user has completed initial onboarding
    var onboardingComplete: Bool
    
    init(controlRepoUrl: String = "", controlRepoPath: String = "", onboardingComplete: Bool = false) {
        self.controlRepoUrl = controlRepoUrl
        self.controlRepoPath = controlRepoPath
        self.onboardingComplete = onboardingComplete
    }
}
