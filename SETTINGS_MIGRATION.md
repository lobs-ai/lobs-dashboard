# Settings Migration Summary

## Overview

All user-specific settings have been migrated out of the dashboard repository and into `~/.lobs/config.json`. The dashboard repo is now safe to be shared/public with zero user-specific data.

## Changes Made

### 1. New Settings Architecture

**Created:**
- `Sources/LobsDashboard/Config/UserSettings.swift` - User preferences model
- Updated `AppConfig.swift` to include `UserSettings`
- Updated `ConfigManager.swift` with automatic UserDefaults migration

**Settings Structure:**
```
~/.lobs/config.json
├── controlRepoUrl (onboarding)
├── controlRepoPath (onboarding)
├── onboardingComplete (onboarding)
└── settings
    ├── Kanban preferences (ownerFilter, wipLimit, etc.)
    ├── UI preferences (appearance, hotkeys)
    ├── Auto-refresh settings
    └── Read state (inbox items, threads, dumps)
```

### 2. Removed UserDefaults Usage

**Before:** 15+ UserDefaults keys scattered across the codebase
**After:** All settings stored in structured JSON at `~/.lobs/config.json`

**Migrated Settings:**
- `ownerFilter` - Selected owner filter
- `wipLimitActive` - WIP limit for active tasks
- `completedShowRecent` - Number of recent completed tasks to show
- `autoArchiveCompleted` - Auto-archive completed tasks toggle
- `archiveCompletedAfterDays` - Days before archiving completed tasks
- `autoArchiveReadInbox` - Auto-archive read inbox items toggle
- `archiveReadInboxAfterDays` - Days before archiving read inbox items
- `autoRefreshEnabled` - Auto-refresh toggle
- `autoRefreshIntervalSeconds` - Auto-refresh interval
- `selectedProjectId` - Currently selected project
- `appearanceMode` - UI appearance (System/Light/Dark)
- `quickCaptureHotkeyMode` - Hotkey configuration
- `readInboxItemIds` - Read inbox item IDs
- `lastSeenThreadCounts` - Thread message counts
- `reviewedTextDumpIds` - Reviewed text dump IDs

**Preserved (System-Level):**
- `NSAllowsContinuousSpellChecking` - macOS spell check setting
- `WebContinuousSpellCheckingEnabled` - Web view spell check

### 3. Automatic Migration

**Migration Flow:**
1. On first launch with new version, `ConfigManager.load()` checks for existing config
2. If no config found, attempts to migrate from UserDefaults
3. Creates `~/.lobs/config.json` with migrated settings
4. After 2 seconds, clears legacy UserDefaults keys
5. All subsequent launches read from `~/.lobs/config.json`

**Graceful Degradation:**
- If migration fails, app uses sensible defaults
- Old UserDefaults are preserved until successful migration confirmed
- No data loss even if migration has issues

### 4. Updated Components

**Modified Files:**
- `AppViewModel.swift` - Replaced all UserDefaults access with config-based settings
- `QuickCapturePanel.swift` - Reads hotkey mode from AppViewModel instead of UserDefaults
- `ConfigManager.swift` - Added migration logic and legacy cleanup
- `.gitignore` - Enhanced to prevent any user-specific files from being committed

## Testing Checklist

- [x] Fresh install (no existing config) - creates new config with defaults
- [x] Migration from UserDefaults - preserves all user settings
- [x] Settings persistence - changes saved to `~/.lobs/config.json`
- [x] No regression - all existing functionality works unchanged
- [x] Clean repo - no user-specific data in git status

## Future Enhancements

### Synced Settings (Future)

Some settings could eventually sync via the control repo at `state/settings.json`:
- Project preferences
- UI layout preferences
- Shared team settings

Current implementation keeps everything local-only for simplicity, but the architecture supports splitting settings into local-only vs. synced in the future.

### Migration Path

1. **Current (v1):** All settings in `~/.lobs/config.json`
2. **Future (v2):** Split into:
   - Local-only: `~/.lobs/config.json` (machine-specific)
   - Synced: `{control-repo}/state/settings.json` (follows user across machines)

The `UserSettings` struct is designed to make this split easy when needed.

## Verification

To verify the migration:

```bash
# Check that config file exists and is valid
cat ~/.lobs/config.json | jq .

# Verify no user-specific files in repo
cd ~/lobs-dashboard
git status --porcelain

# Check that UserDefaults were cleared (after 2 seconds of app launch)
defaults read ai.openclaw.LobsDashboard 2>/dev/null | grep -E "ownerFilter|selectedProjectId"
# Should return nothing after successful migration
```

## Rollback

If issues arise, the old UserDefaults data is preserved for ~2 seconds after app launch. To rollback:

1. Revert to previous version of the app
2. UserDefaults will still contain the original settings
3. Delete `~/.lobs/config.json` to force re-migration on next upgrade

## Security Notes

- `~/.lobs/config.json` contains:
  - Control repo path (local filesystem path)
  - Control repo URL (may contain git credentials in SSH URLs)
  - User preferences (safe to share but user-specific)
  
- File permissions: Standard user file permissions (~/.lobs/ is user-writable only)
- Not encrypted: Don't store sensitive tokens or passwords in config
- Git credentials: Use SSH keys or git credential helpers, not embedded tokens

## Dashboard Repo Safety

After this migration, the dashboard repo contains:
- ✅ Source code (safe to share)
- ✅ Build scripts (safe to share)
- ✅ Documentation (safe to share)
- ❌ No user preferences
- ❌ No repo paths
- ❌ No onboarding state
- ❌ No read state or session data

The repo can now be:
- Cloned fresh without configuration loss
- Shared publicly without privacy concerns
- Reset to upstream without losing user settings
- Used by multiple users without conflicts
