import Foundation

/// Manages application configuration persistence at ~/Library/Application Support/Lobs/config.json
class ConfigManager {
    /// Configuration directory (Application Support to avoid TCC prompts)
    private static var configDirectory: URL { LobsPaths.appSupport }
    
    /// Configuration file location
    private static var configFile: URL { LobsPaths.configFile }
    
    /// Load configuration from disk, migrating from UserDefaults if needed
    /// - Returns: AppConfig if file exists and is valid, or default config with migrated settings
    static func load() -> AppConfig? {
        // Try loading from disk first
        if FileManager.default.fileExists(atPath: configFile.path) {
            do {
                let data = try Data(contentsOf: configFile)
                let decoder = JSONDecoder()
                var config = try decoder.decode(AppConfig.self, from: data)
                
                // Migrate any remaining UserDefaults on load (belt and suspenders)
                let migrated = migrateUserDefaults()
                if let migrated = migrated {
                    config.settings = mergeSettings(existing: config.settings, migrated: migrated)
                }
                
                return config
            } catch {
                // If decode fails, try to recover by migrating from UserDefaults
                print("⚠️ Failed to decode config from \(configFile.path): \(error)")
                print("⚠️ Attempting recovery via UserDefaults migration...")
            }
        }
        
        // No config file or decode failed - migrate from UserDefaults if available
        if let migrated = migrateUserDefaults() {
            print("ℹ️ Migrated settings from UserDefaults to \(configFile.path)")
            let config = AppConfig(settings: migrated)
            // Try to save migrated config
            try? save(config)
            return config
        }
        
        return nil
    }
    
    /// Migrate settings from UserDefaults to UserSettings
    /// Returns nil if no UserDefaults data found
    private static func migrateUserDefaults() -> UserSettings? {
        let defaults = UserDefaults.standard
        
        // Check if any settings exist in UserDefaults
        let hasAnySettings = defaults.object(forKey: "ownerFilter") != nil ||
                            defaults.object(forKey: "selectedProjectId") != nil ||
                            defaults.object(forKey: "appearanceMode") != nil
        
        guard hasAnySettings else { return nil }
        
        var settings = UserSettings()
        
        // Migrate each setting with safe defaults
        if let ownerFilter = defaults.string(forKey: "ownerFilter") {
            settings.ownerFilter = ownerFilter
        }
        
        let wip = defaults.integer(forKey: "wipLimitActive")
        if wip > 0 { settings.wipLimitActive = wip }
        
        let csr = defaults.integer(forKey: "completedShowRecent")
        if csr > 0 { settings.completedShowRecent = csr }
        
        if defaults.object(forKey: "autoArchiveCompleted") != nil {
            settings.autoArchiveCompleted = defaults.bool(forKey: "autoArchiveCompleted")
        }
        
        let archiveDays = defaults.integer(forKey: "archiveCompletedAfterDays")
        if archiveDays > 0 { settings.archiveCompletedAfterDays = archiveDays }
        
        if defaults.object(forKey: "autoArchiveReadInbox") != nil {
            settings.autoArchiveReadInbox = defaults.bool(forKey: "autoArchiveReadInbox")
        }
        
        let inboxDays = defaults.integer(forKey: "archiveReadInboxAfterDays")
        if inboxDays > 0 { settings.archiveReadInboxAfterDays = inboxDays }
        
        if defaults.object(forKey: "autoRefreshEnabled") != nil {
            settings.autoRefreshEnabled = defaults.bool(forKey: "autoRefreshEnabled")
        }
        
        let interval = defaults.integer(forKey: "autoRefreshIntervalSeconds")
        if interval > 0 { settings.autoRefreshIntervalSeconds = interval }
        
        if let projectId = defaults.string(forKey: "selectedProjectId") {
            settings.selectedProjectId = projectId
        }
        
        let appearance = defaults.integer(forKey: "appearanceMode")
        settings.appearanceMode = appearance
        
        let qc = defaults.integer(forKey: "quickCaptureHotkeyMode")
        settings.quickCaptureHotkeyMode = qc
        
        // Migrate arrays
        if let readItems = defaults.stringArray(forKey: "readInboxItemIds") {
            settings.readInboxItemIds = readItems
        }
        
        if let data = defaults.data(forKey: "lastSeenThreadCounts"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            settings.lastSeenThreadCounts = decoded
        }
        
        if let reviewedIds = defaults.stringArray(forKey: "reviewedTextDumpIds") {
            settings.reviewedTextDumpIds = reviewedIds
        }
        
        return settings
    }
    
    /// Merge migrated settings with existing settings (prefer existing)
    private static func mergeSettings(existing: UserSettings, migrated: UserSettings) -> UserSettings {
        var merged = existing
        
        // Only use migrated values if existing is still at default
        if merged.ownerFilter == "all" && migrated.ownerFilter != "all" {
            merged.ownerFilter = migrated.ownerFilter
        }
        if merged.selectedProjectId == "default" && migrated.selectedProjectId != "default" {
            merged.selectedProjectId = migrated.selectedProjectId
        }
        
        // Merge read state arrays (union)
        merged.readInboxItemIds = Array(Set(merged.readInboxItemIds + migrated.readInboxItemIds))
        merged.reviewedTextDumpIds = Array(Set(merged.reviewedTextDumpIds + migrated.reviewedTextDumpIds))
        
        // Merge thread counts (prefer higher value)
        for (key, value) in migrated.lastSeenThreadCounts {
            if let existing = merged.lastSeenThreadCounts[key] {
                merged.lastSeenThreadCounts[key] = max(existing, value)
            } else {
                merged.lastSeenThreadCounts[key] = value
            }
        }
        
        return merged
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
        var data = try encoder.encode(config)
        // Convert to Python-compatible format (": " instead of " : ")
        if var jsonString = String(data: data, encoding: .utf8) {
            jsonString = jsonString.replacingOccurrences(of: " : ", with: ": ")
            data = Data(jsonString.utf8)
        }
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
    
    /// Clear UserDefaults settings after successful migration
    /// Call this after confirming the new config file is working
    static func clearLegacyUserDefaults() {
        let defaults = UserDefaults.standard
        let keys = [
            "ownerFilter",
            "wipLimitActive",
            "completedShowRecent",
            "autoArchiveCompleted",
            "archiveCompletedAfterDays",
            "autoArchiveReadInbox",
            "archiveReadInboxAfterDays",
            "autoRefreshEnabled",
            "autoRefreshIntervalSeconds",
            "selectedProjectId",
            "appearanceMode",
            "quickCaptureHotkeyMode",
            "readInboxItemIds",
            "lastSeenThreadCounts",
            "reviewedTextDumpIds"
        ]
        
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        
        defaults.synchronize()
        print("ℹ️ Cleared legacy UserDefaults settings")
    }
}
