import Foundation

/// Manages application configuration persistence at ~/.lobs/config.json
class ConfigManager {
    /// Configuration file location
    private static let configDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lobs")
    }()
    
    private static let configFile: URL = {
        configDirectory.appendingPathComponent("config.json")
    }()
    
    /// Load configuration from disk
    /// - Returns: AppConfig if file exists and is valid, nil otherwise
    static func load() -> AppConfig? {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: configFile)
            let decoder = JSONDecoder()
            let config = try decoder.decode(AppConfig.self, from: data)
            return config
        } catch {
            // Log error but return nil for graceful degradation
            print("⚠️ Failed to load config from \(configFile.path): \(error)")
            return nil
        }
    }
    
    /// Save configuration to disk
    /// - Parameter config: AppConfig to persist
    /// - Throws: File system or encoding errors
    static func save(_ config: AppConfig) throws {
        // Create ~/.lobs directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: configDirectory.path) {
            try FileManager.default.createDirectory(
                at: configDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)
    }
    
    /// Check if configuration file exists
    /// - Returns: true if config file exists, false otherwise
    static func exists() -> Bool {
        return FileManager.default.fileExists(atPath: configFile.path)
    }
    
    /// Delete configuration file (for re-onboarding)
    /// - Throws: File system errors if deletion fails
    static func reset() throws {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            // No config to delete - not an error
            return
        }
        
        try FileManager.default.removeItem(at: configFile)
    }
}
