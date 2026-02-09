# Dashboard Performance Fixes

## Problem
The dashboard was freezing and lagging, particularly during git operations and data reloading.

## Root Causes Identified

1. **Synchronous I/O on Main Thread**
   - After git sync, all data loading happened synchronously on the main actor
   - Heavy file operations (`loadProjects`, `loadTasks`, `loadInboxItems`, etc.) blocked the UI

2. **Stacking Git Operations**
   - Multiple git status checks happening in rapid succession
   - No throttling on expensive operations like `checkControlRepoStatus()` and `checkForDashboardUpdate()`

3. **Excessive Reloading**
   - All secondary data (research, tracker, inbox, worker status) loaded synchronously
   - Even when unchanged, all data was reprocessed on every refresh

## Solutions Implemented

### 1. Background Data Loading
Moved heavy data loading operations off the main thread:

```swift
// Before: All on main thread
let store = LobsControlStore(repoRoot: repoURL)
projects = try store.loadProjects()
tasks = try await store.loadTasks()
loadResearchData(store: store)
loadTrackerData(store: store)
// ... blocks UI

// After: Background loading
let loadedData = await Task.detached {
  let store = LobsControlStore(repoRoot: repoURL)
  // Load data here...
  return (projects, tasks, hasGitHub, syncTime)
}.value

await MainActor.run {
  // Only update UI properties here
  self.projects = loadedData.projects
  self.tasks = loadedData.tasks
}
```

### 2. Async Helper Functions
Created async versions of all heavy data loaders:
- `loadResearchDataAsync(store:)`
- `loadTrackerDataAsync(store:)`
- `loadInboxItemsAsync(store:)`
- `loadWorkerStatusAsync(store:)`
- `checkForDashboardUpdateAsync()`
- `checkControlRepoStatusAsync()`
- `updatePendingChangesCountAsync()`

### 3. Prioritized Loading
Separated critical from secondary data:

```swift
// Critical data loads first (high priority)
tasks = data.tasks
projects = data.projects

// Secondary data loads in background (utility priority)
Task.detached(priority: .utility) {
  await self.loadResearchDataAsync(store: store)
  await self.loadInboxItemsAsync(store: store)
  // etc.
}
```

### 4. Operation Throttling
Added caching timestamps to prevent excessive git operations:

```swift
private var lastControlRepoStatusCheck: Date? = nil
private var lastPendingChangesUpdate: Date? = nil

// In checkControlRepoStatusAsync():
if let last = lastControlRepoStatusCheck,
   Date().timeIntervalSince(last) < 10 {
  return  // Skip if checked within last 10 seconds
}
```

Throttle intervals:
- Control repo status: 10 seconds
- Pending changes count: 5 seconds
- Dashboard updates: 5 minutes

### 5. Better Async Flow
Ensured proper async/await usage with MainActor isolation:

```swift
// Sync git operations
try await syncRepoAsync(repoURL: repoURL)

// Load in background
let data = await Task.detached { ... }.value

// Update UI on main thread
await MainActor.run { ... }
```

## Expected Results

1. **Responsive UI**: Git operations no longer block the main thread
2. **Faster Perceived Load**: Critical data (tasks, projects) loads first
3. **Reduced Git Overhead**: Status checks happen at most once every 5-10 seconds
4. **Background Updates**: Secondary data loads don't interfere with user interaction

## Testing

To verify the fixes:
1. Open the dashboard with a large control repo
2. Navigate between projects - should be instant
3. Manual refresh (⌘R) - UI should stay responsive during sync
4. Auto-refresh (every 30s) - should not cause noticeable lag
5. Git operations (create task, edit) - should not freeze the UI

## Files Modified

- `Sources/LobsDashboard/AppViewModel.swift`:
  - `silentReload()` - background data loading
  - `reload()` - background data loading
  - Added 7 new async helper functions
  - Added throttling timestamps and logic
