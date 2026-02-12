# API Migration Status

## ✅ Completed

### 1. APIService.swift
Created `Sources/LobsDashboard/APIService.swift` with:
- Full HTTP client using URLSession
- JSON encoding/decoding with snake_case ↔ camelCase conversion
- ISO 8601 date handling
- All major endpoints mapped from LobsControlStore interface:
  - Projects (CRUD, archive)
  - Tasks (CRUD, status updates, work state, review state, archive)
  - Inbox (items, threads, messages)
  - Agent Documents
  - Worker Status & History
  - Agent Statuses
  - Templates

### 2. AppConfig.swift
- Added `serverURL` property (default: "http://localhost:8000")
- Updated initializer to include serverURL parameter

## 🚧 In Progress

### AppViewModel.swift Migration
The AppViewModel.swift file needs to be updated to use APIService instead of LobsControlStore.

#### Pattern to Follow:

**Before (git-based):**
```swift
func silentReload() {
  let store = LobsControlStore(repoRoot: repoURL)
  let projects = try store.loadProjects()
  let tasks = try await store.loadTasks()
  ...
}
```

**After (API-based):**
```swift
func silentReload() async {
  guard let api = makeAPIService() else {
    flashError("API service not configured")
    return
  }
  let projects = try await api.loadProjects()
  let tasks = try await api.loadTasks()
  ...
}

private func makeAPIService() -> APIService? {
  guard let serverURL = config?.serverURL, !serverURL.isEmpty else {
    return nil
  }
  return try? APIService(baseURLString: serverURL)
}
```

#### Key Methods to Update:

1. **Data Loading**
   - `silentReload()` - line ~754
   - `reload()` - line ~862
   - `loadResearchData()` - line ~2102
   - `loadAgentDocuments()` - line ~2132
   - `loadTrackerData()` - line ~2288
   - `loadInboxItems()` - line ~2526
   - `loadWorkerStatus()` - line ~2773
   - `loadAgentStatuses()` - (search for method)
   - `loadTemplates()` - (search for method)

2. **Task Operations**
   - `setStatus()` - search for method
   - `setWorkState()` - search for method
   - `setReviewState()` - search for method
   - `setSortOrder()` - search for method
   - `setTitleAndNotes()` - search for method
   - `addTask()` - search for method
   - `deleteTask()` - search for method
   - `archiveTask()` - search for method

3. **Project Operations**
   - `renameProject()` - search for method
   - `updateProjectNotes()` - search for method
   - `deleteProject()` - search for method
   - `archiveProject()` - search for method

4. **Inbox Operations**
   - `saveInboxThread()` - search for method
   - `loadInboxThread()` - search for method

#### Methods to Keep Git-Based:

These methods are git/filesystem specific and don't have API equivalents yet:
- All git sync operations (pull, push, commit, rebase, etc.)
- `readArtifact()` - artifacts are still file-based
- `loadProjectReadme()` - READMEs are still file-based
- Research doc operations (doc-based content not yet in API)
- Tracker operations (not yet in API)
- Auto-archive operations (should be server-side eventually)

## 📝 Migration Steps

### Step 1: Add API Service Helper to AppViewModel

Add after the `config` property:
```swift
/// Create an API service instance using the configured server URL
private func makeAPIService() -> APIService? {
  guard let serverURL = config?.serverURL, !serverURL.isEmpty else {
    return nil
  }
  do {
    return try APIService(baseURLString: serverURL)
  } catch {
    print("⚠️ Failed to create API service: \(error)")
    return nil
  }
}
```

### Step 2: Update Core Data Loading Methods

Replace LobsControlStore calls with API calls in these methods:
- `silentReload()`
- `reload()`
- `loadAgentDocuments()`
- `loadWorkerStatus()`

### Step 3: Update Task Operation Methods

Replace Store calls in:
- Task status/state update methods
- Task creation/deletion methods
- Project CRUD methods

### Step 4: Update Async Data Loading Helpers

Add async versions that use the API:
- `loadResearchDataAsync()`
- `loadTrackerDataAsync()`
- `loadInboxItemsAsync()`
- `loadWorkerStatusAsync()`
- `loadAgentStatusesAsync()`
- `loadAgentDocumentsAsync()`

### Step 5: Test & Validate

1. Ensure the app compiles
2. Verify all API endpoints are reachable
3. Test CRUD operations for tasks and projects
4. Verify data loads correctly from the server

## ⚠️ Important Notes

1. **Git Operations**: Keep all git sync/push/pull/commit/rebase logic intact. These are independent of the API and handle version control of the repo state.

2. **Fallback Strategy**: The LobsControlStore code remains in the codebase as a fallback option. Don't delete Store.swift.

3. **Error Handling**: API calls should gracefully handle network errors and fall back to showing cached data or appropriate error messages.

4. **Date Handling**: The API uses ISO 8601 dates. APIService handles conversion automatically via JSONDecoder.

5. **snake_case ↔ camelCase**: APIService handles key conversion automatically via `keyDecodingStrategy = .convertFromSnakeCase`.

6. **Missing API Endpoints**: Some features (research docs, tracker, artifacts) don't have API endpoints yet. These should continue using file-based Store methods for now.

## 🎯 Next Steps

1. Add `makeAPIService()` helper to AppViewModel
2. Systematically update each data loading method
3. Update each task/project operation method
4. Test the migration
5. Commit and push changes
6. Update this status document with completion notes

## 📊 Progress Tracking

- [x] APIService.swift created
- [x] AppConfig.swift updated
- [ ] AppViewModel.swift - add API service helper
- [ ] AppViewModel.swift - update data loading methods
- [ ] AppViewModel.swift - update task operations
- [ ] AppViewModel.swift - update project operations
- [ ] AppViewModel.swift - update inbox operations
- [ ] Testing and validation
- [ ] Git commit and push
