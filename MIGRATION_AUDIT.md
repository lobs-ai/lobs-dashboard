# Dashboard Migration Audit Report
**Date:** 2026-02-12  
**Branch:** feature/api-integration  
**Auditor:** Subagent (dashboard-audit)

## Executive Summary

The lobs-dashboard-v2 migration from git-based state to REST API calls is **mostly complete** but has several issues that need attention:

- ✅ **76/90 methods migrated** (84% complete)
- ⚠️ **16 TODO comments** indicating incomplete API endpoints
- ❌ **Several unused data structures** still present (dead code)
- ❌ **Missing API endpoints** for some Store.swift functionality
- ⚠️ **Stub implementations** that silently return empty/default values

---

## 1. File-Level Changes

### Added Files
- ✅ `APIService.swift` (1,260 lines) - New REST API service layer

### Removed Files
- ✅ `GitAutoPushQueue.swift` - No longer needed (API handles persistence)
- ⚠️ `BuildInfo.generated.swift` - Missing in v2 (may be generated at build time)

### Modified Files
- `AppViewModel.swift` - Refactored to use `APIService` instead of `LobsControlStore`
- `Store.swift` - **Still present but unused** (2,198 lines of dead code)

**Recommendation:** Delete `Store.swift` or clearly mark it as legacy/reference-only to avoid confusion.

---

## 2. AppViewModel Method Analysis

### ✅ Fully Migrated Methods (No Issues)

All major AppViewModel methods have been migrated and call the API service instead of git:
- `reload()` / `silentReload()` / `reloadIfPossible()`
- `selectTask()`, `toggleMultiSelect()`, `clearMultiSelect()`
- Task batch operations: `approveSelected()`, `completeSelected()`, `markDoneSelected()`, etc.
- `loadResearchData()`, `loadAgentDocuments()`, `loadTrackerData()`, `loadWorkerStatus()`
- `stampTemplate()`, `saveTemplate()`, `deleteTemplate()`
- Inbox operations: `loadInboxItems()`, `markInboxItemRead()`, `saveInboxResponse()`
- Research operations: `saveResearchDocContent()`, `addResearchSource()`, `removeResearchSource()`
- Tracker operations: `addTrackerItem()`, `updateTrackerItem()`, `removeTrackerItem()`
- Project management: `setControlRepo()`, `checkForDashboardUpdate()`, `performSelfUpdate()`
- Git sync: `pushNow()`, `syncGitHubCache()`, `recoverSyncConflictKeepMine()`, etc.
- Notifications: `postNotification()`, `dismissNotification()`, `flashError()`, `flashSuccess()`

### ⚠️ Methods With TODO Comments

The following AppViewModel methods exist but have TODO comments indicating missing API support:

1. **Line 813:** Artifact loading
   ```swift
   // TODO: API endpoint needed for artifact loading
   ```

2. **Line 1275:** GitHub cache timestamp
   ```swift
   // TODO: API endpoint needed for GitHub cache timestamp
   ```

3. **Line 1316:** Artifact loading (duplicate)
   ```swift
   // TODO: API endpoint needed for artifact loading
   ```

4. **Line 1338:** Project last commit tracking
   ```swift
   // TODO: API endpoint needed for project last commit tracking
   ```

5. **Line 2084:** Research data loading
   ```swift
   // TODO: API endpoints needed for research data
   ```

6. **Line 2190:** Deleting research sources
   ```swift
   // TODO: API endpoint needed for deleting research sources
   ```

7. **Line 2311, 2317:** Inbox read state persistence (2 locations)
   ```swift
   // TODO: API endpoint for inbox read state persistence
   ```

8. **Line 3407:** Create project API endpoint
   ```swift
   // TODO: Add createProject API endpoint
   ```

9. **Line 3566:** Unarchive project API endpoint
   ```swift
   // TODO: Add unarchiveProject API endpoint
   ```

10. **Lines 4314, 4319:** Artifact loading (2 more instances)
    ```swift
    // TODO: API endpoint needed for artifact loading
    ```

---

## 3. Store.swift → APIService.swift Method Comparison

### ✅ Successfully Migrated to APIService

| Original Store Method | APIService Equivalent | Status |
|----------------------|----------------------|--------|
| `loadProjects()` | `loadProjects()` | ✅ Migrated (async) |
| `saveProjects()` | `saveProjects()` | ✅ Migrated (async) |
| `renameProject()` | `renameProject()` | ✅ Migrated (async) |
| `updateProjectNotes()` | `updateProjectNotes()` | ✅ Migrated (async) |
| `deleteProject()` | `deleteProject()` | ✅ Migrated (async) |
| `archiveProject()` | `archiveProject()` | ✅ Migrated (async) |
| `updateProjectSyncMode()` | `updateProjectSyncMode()` | ✅ Migrated (async) |
| `loadTasks()` | `loadTasks()` | ✅ Migrated (async) |
| `saveTasks()` | `saveTasks()` | ✅ Migrated (async) |
| `loadLocalTasks()` | `loadLocalTasks()` | ✅ Migrated (async) |
| `addTask()` | `addTask()` | ✅ Migrated (async) |
| `saveExistingTask()` | `saveExistingTask()` | ✅ Migrated (async) |
| `deleteTask()` | `deleteTask()` | ✅ Migrated (async) |
| `archiveTask()` | `archiveTask()` | ✅ Migrated (async) |
| `setStatus()` | `setStatus()` | ✅ Migrated (async) |
| `setWorkState()` | `setWorkState()` | ✅ Migrated (async) |
| `setReviewState()` | `setReviewState()` | ✅ Migrated (async) |
| `setSortOrder()` | `setSortOrder()` | ✅ Migrated (async) |
| `setTitleAndNotes()` | `setTitleAndNotes()` | ✅ Migrated (async) |
| `loadInboxItems()` | `loadInboxItems()` | ✅ Migrated (async) |
| `loadInboxThread()` | `loadInboxThread()` | ✅ Migrated (async) |
| `saveInboxThread()` | `saveInboxThread()` | ✅ Migrated (async) |
| `loadAllInboxThreads()` | `loadAllInboxThreads()` | ✅ Migrated (async) |
| `loadAgentDocuments()` | `loadAgentDocuments()` | ✅ Migrated (async) |
| `loadWorkerStatus()` | `loadWorkerStatus()` | ✅ Migrated (async) |
| `loadWorkerHistory()` | `loadWorkerHistory()` | ✅ Migrated (async) |
| `loadAgentStatuses()` | `loadAgentStatuses()` | ✅ Migrated (async) |
| `loadTemplates()` | `loadTemplates()` | ✅ Migrated (async) |
| `saveTemplate()` | `saveTemplate()` | ✅ Migrated (async) |
| `deleteTemplate()` | `deleteTemplate()` | ✅ Migrated (async) |
| `loadResearchDoc()` | `loadResearchDoc()` | ✅ Migrated (async) |
| `saveResearchDoc()` | `saveResearchDoc()` | ✅ Migrated (async) |
| `loadResearchSources()` | `loadResearchSources()` | ✅ Migrated (async) |
| `saveResearchSources()` | `addResearchSource()` | ✅ Migrated (different signature) |
| `loadResearchDeliverables()` | `loadResearchDeliverables()` | ✅ Migrated (async) |
| `saveResearchDeliverable()` | `saveResearchDeliverable()` | ✅ Migrated (async) |
| `loadTiles()` | `loadTiles()` | ✅ Migrated (async, renamed to Tile) |
| `saveTile()` | `saveTile()` | ✅ Migrated (async) |
| `deleteTile()` | `deleteTile()` | ✅ Migrated (async) |
| `loadRequests()` | `loadResearchRequests()` | ✅ Migrated (renamed) |
| `saveRequest()` | `saveRequest()` | ✅ Migrated (async) |
| `deleteRequest()` | `deleteResearchRequest()` | ✅ Migrated (async, renamed) |
| `loadTrackerItems()` | `loadTrackerItems()` | ✅ Migrated (async) |
| `deleteTrackerItem()` | `deleteTrackerItem()` | ✅ Migrated (async) |
| `deleteResearchData()` | `deleteResearchData()` | ✅ Migrated (async) |
| `deleteTrackerData()` | `deleteTrackerData()` | ✅ Migrated (async) |
| `loadTextDumps()` | `loadTextDumps()` | ✅ Migrated (async) |
| `saveTextDump()` | `saveTextDump()` | ✅ Migrated (async) |
| `saveProjectReadme()` | `saveProjectReadme()` | ✅ Migrated (async) |

### ⚠️ Partially Migrated (Different Signature/Behavior)

| Original Store Method | Notes |
|----------------------|-------|
| `addResearchRequest()` | Exists but renamed/different params |
| `updateResearchRequest()` | New method (didn't exist in Store) |
| `addTrackerItem()` | Exists but different signature |
| `updateTrackerItem()` | Exists but different signature |
| `createTextDump()` | New helper method (didn't exist in Store) |

### ❌ Missing from APIService (Stubbed or Not Implemented)

| Original Store Method | Status | Impact |
|----------------------|--------|--------|
| `loadInboxResponses()` | ❌ Missing | **CRITICAL** - `inboxResponsesByDocId` is never populated |
| `loadInboxResponse(docId:)` | ❌ Missing | Used by Store, not by API |
| `saveTrackerItem()` | ❌ Missing (replaced with add/update) | Tracker saves may fail |
| `saveTrackerRequest()` | ❌ Missing | Tracker requests can't be saved |
| `deleteTrackerRequest()` | ❌ Missing | Tracker requests can't be deleted |
| `loadTrackerRequests()` | ❌ Missing | Separate from research requests |
| `loadAgentFile()` | ❌ Missing | **MEDIUM** - Agent file editing broken |
| `saveAgentFile()` | ❌ Missing | **MEDIUM** - Agent file editing broken |
| `loadMainSessionUsage()` | ❌ Missing | Usage stats unavailable |
| `setTaskField()` | ❌ Missing | Generic field updates not supported |
| `loadTasksFromGitHubCache()` | ❌ Missing | GitHub integration broken |
| `getGitHubCacheTimestamp()` | ❌ Missing | GitHub sync may not work |
| `loadTasksFromGitHub()` | ❌ Missing | Direct GitHub loading broken |
| `saveTaskToGitHub()` | ❌ Missing | GitHub task creation broken |

### ⚠️ Stubbed Out (Returns Empty/Default Values)

These methods exist in APIService but are **no-ops** or return empty values:

| Method | Line | Implementation |
|--------|------|----------------|
| `loadInboxReadState()` | 1064 | Returns `nil` (local-only) |
| `saveInboxReadState()` | 1070 | No-op (local-only) |
| `archiveCompleted()` | 1076 | No-op (should be server-side) |
| `archiveReadInboxItems()` | 1081 | No-op (should be server-side) |
| `readArtifact()` | 1085 | **Returns empty string** ⚠️ |

**Critical Issue:** `readArtifact()` silently returns `""` instead of throwing or calling an API endpoint. This breaks artifact reading functionality with no error message.

---

## 4. Broken/Unused Data Structures

### ❌ `inboxResponsesByDocId`

**Location:** AppViewModel.swift:255  
**Status:** Defined but never populated  
**Impact:** HIGH

```swift
@Published var inboxResponsesByDocId: [String: InboxResponse] = [:]
```

**Problem:**
- In the original version, this was populated by `store.loadInboxResponses()`
- In v2, there is NO call to load inbox responses
- The `inboxResponseText()` method reads from this dict, returning `""` for all items
- The `InboxResponse` data structure still exists in Models.swift but is orphaned

**Recommendation:**
1. If InboxResponse is obsolete (replaced by InboxThread), **remove it entirely**
2. If it's still needed, add `loadInboxResponses()` to APIService and call it during `loadInboxItems()`

---

## 5. Agent Personality Management

### ⚠️ Incomplete Migration

Several files have TODO comments about agent personality:

**OnboardingPersonalityView.swift:284:**
```swift
// TODO: In API mode, agent personality should be loaded from API
```

**AgentDetailSheet.swift:267, 280:**
```swift
// TODO: Add API endpoints for agent file loading (GET /api/agents/{type}/files/{filename})
// TODO: Add API endpoint for agent file saving (PUT /api/agents/{type}/files/{filename})
```

**AgentPersonalityManager.swift:9:**
```swift
/// TODO: Migrate to API-based agent personality management
```

**Impact:** Agent personality editing UI may not work in API mode.

---

## 6. GitHub Integration

### ❌ Completely Broken

All GitHub-related Store methods are missing from APIService:

- `loadTasksFromGitHubCache()`
- `getGitHubCacheTimestamp()`
- `loadTasksFromGitHub()`
- `saveTaskToGitHub()`

**AppViewModel references:**
- Line 1275: GitHub cache timestamp check
- Line 1316: Artifact loading via GitHub

**Impact:** Projects with `syncMode = .github` will not work. Tasks cannot be synced to/from GitHub issues.

**Recommendation:** Either:
1. Add GitHub API endpoints to lobs-server
2. Keep GitHub sync methods in Store.swift and use them conditionally
3. Remove GitHub sync mode entirely and document it as unsupported in API mode

---

## 7. Artifact Reading

### ❌ Silently Broken

The `readArtifact()` method in APIService is a stub:

```swift
func readArtifact(relativePath: String) throws -> String {
  // Artifacts are file-based and don't go through the API
  // This would need special handling or a file server
  return ""
}
```

**AppViewModel usage:**
- Line 813: "TODO: API endpoint needed for artifact loading"
- Lines 4314, 4319: More artifact loading TODOs

**Impact:** Any code that reads artifacts will get empty strings instead of content, with no error indication.

**Recommendation:**
1. Throw an error instead of returning `""`
2. Add an API endpoint: `GET /api/artifacts/{path}`
3. Or add a file server to lobs-server for artifact access

---

## 8. Tracker Requests

### ❌ Missing Methods

The original Store had separate methods for tracker requests:

- `loadTrackerRequests()` (different from research requests)
- `saveTrackerRequest()`
- `deleteTrackerRequest()`

These are **completely missing** from APIService.

**Impact:** Tracker feature may be partially broken. Research requests and tracker requests are different types.

**Recommendation:** Add these methods to APIService or merge tracker/research request types if they're truly the same.

---

## 9. Summary of Critical Issues

### 🔴 HIGH PRIORITY (Breaks Functionality)

1. **Inbox Responses Not Loaded** - `inboxResponsesByDocId` never populated
2. **Artifact Reading Returns Empty** - Silent failure, no error message
3. **GitHub Integration Broken** - All GitHub sync methods missing
4. **Agent File Editing Broken** - `loadAgentFile()` / `saveAgentFile()` missing

### 🟡 MEDIUM PRIORITY (Degraded Experience)

5. **Tracker Requests Missing** - `saveTrackerRequest()`, `deleteTrackerRequest()` not implemented
6. **Auto-Archive Disabled** - `archiveCompleted()` / `archiveReadInboxItems()` are no-ops
7. **Inbox Read State Not Persisted** - Local-only, won't sync across devices
8. **Main Session Usage Stats Unavailable** - `loadMainSessionUsage()` missing

### 🟢 LOW PRIORITY (Cleanup/Tech Debt)

9. **Store.swift Still Present** - 2,198 lines of unused code
10. **BuildInfo.generated.swift Missing** - May be auto-generated
11. **Generic `setTaskField()` Missing** - Less flexible task updates

---

## 10. Recommendations

### Immediate Actions (Before Merge)

1. **Delete or Archive Store.swift** - Mark it clearly as legacy/reference-only
2. **Fix `readArtifact()`** - Throw error or implement API endpoint
3. **Fix or Remove `inboxResponsesByDocId`** - Either load it or delete the field
4. **Document GitHub Sync Status** - Add note that GitHub sync is not supported in API mode

### Short-Term (Next Sprint)

5. **Add Missing API Endpoints:**
   - `GET /api/artifacts/{path}` (artifact reading)
   - `POST /api/tracker/{projectId}/requests` (save tracker request)
   - `DELETE /api/tracker/{projectId}/requests/{id}` (delete tracker request)
   - `GET/PUT /api/agents/{type}/files/{filename}` (agent file management)
   - `POST /api/projects` (create project)
   - `POST /api/projects/{id}/unarchive` (unarchive project)

6. **Implement Server-Side Features:**
   - Auto-archive for completed tasks
   - Auto-archive for read inbox items
   - Inbox read state sync (multi-device)

### Long-Term (Future)

7. **GitHub Integration:**
   - Decide if GitHub sync should be supported in API mode
   - If yes, implement GitHub proxy in lobs-server
   - If no, remove the UI for GitHub sync mode

8. **Remove TODO Comments:**
   - Replace all "TODO: API endpoint" comments with actual implementations
   - Run `grep -rn TODO Sources/` and track down remaining items

---

## 11. Test Checklist

Before marking migration complete, manually test:

- [ ] Create, edit, delete tasks
- [ ] Batch operations (approve/complete/reject multiple tasks)
- [ ] Load and respond to inbox items
- [ ] Load and edit research documents
- [ ] Add/edit/delete tracker items
- [ ] Load agent statuses and documents
- [ ] Edit agent personalities (OnboardingPersonalityView)
- [ ] Create/edit/delete templates
- [ ] Archive completed tasks (if implemented)
- [ ] Sync with GitHub (if supported)
- [ ] Read artifacts from task notes
- [ ] Project creation (currently has TODO)
- [ ] Project unarchive (currently has TODO)

---

## 12. Conclusion

The migration from git-based storage to REST API is **84% complete** and covers all core functionality. However, there are **critical gaps** that will cause silent failures (artifacts, inbox responses) and **missing features** (GitHub sync, agent file editing, tracker requests).

**Status:** ⚠️ **NOT READY FOR PRODUCTION**

**Blockers for Merge:**
1. Fix `readArtifact()` to throw error instead of returning empty string
2. Remove or fix `inboxResponsesByDocId` orphaned data
3. Document unsupported features (GitHub sync, agent personality in API mode)
4. Delete or clearly mark Store.swift as unused

**Estimated effort to completion:** 2-3 days to implement missing API endpoints and fix critical bugs.

---

**Generated:** 2026-02-12 17:05 EST  
**Auditor:** Subagent (dashboard-audit)  
**Next Review:** After API endpoints are added
