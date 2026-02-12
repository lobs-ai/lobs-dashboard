# Contributing to Lobs Dashboard

**Date:** 2026-02-12  
**For:** Developers, AI agents, contributors

This guide helps you work on lobs-dashboard effectively. It covers architecture patterns, common pitfalls, debugging strategies, and testing approaches.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture Overview](#architecture-overview)
3. [Common Pitfalls](#common-pitfalls)
4. [Development Workflow](#development-workflow)
5. [Testing Strategy](#testing-strategy)
6. [Debugging Guide](#debugging-guide)
7. [Code Patterns](#code-patterns)
8. [Pull Request Guidelines](#pull-request-guidelines)

---

## Quick Start

### Prerequisites

- macOS 13.0+ (Ventura or later)
- Xcode 15.0+ or Swift 5.9+
- Git with SSH configured
- A local clone of `lobs-control` repository

### First Build

```bash
# Clone the repository
git clone git@github.com:RafeSymonds/lobs-dashboard.git
cd lobs-dashboard

# Build
swift build

# Run (creates BuildInfo.generated.swift first)
./bin/build && ./bin/run

# Or open in Xcode
open Package.swift
```

**⚠️ Important:** Always use `./bin/build` before running to ensure build info is current.

### Project Structure

```
lobs-dashboard/
├── Sources/LobsDashboard/
│   ├── Config/               # Settings and config management
│   │   ├── AppConfig.swift
│   │   ├── ConfigManager.swift
│   │   └── UserSettings.swift
│   ├── Models/               # Core data models (implicit - in main dir)
│   │   ├── Models.swift      # Task, Project, SyncMode, etc.
│   │   └── Store.swift       # Git-backed persistence
│   ├── Views/                # SwiftUI views (implicit)
│   │   ├── ContentView.swift # Root view
│   │   ├── BoardView.swift   # Kanban board
│   │   ├── InboxView.swift   # Artifact viewer
│   │   ├── ResearchView.swift
│   │   └── ...
│   ├── Services/             # External integrations
│   │   ├── GitHubService.swift
│   │   └── ShellRunner.swift
│   └── ...
├── Tests/                    # Unit and UI tests
├── bin/                      # Build and utility scripts
├── docs/                     # Documentation
└── Package.swift            # Swift package manifest
```

---

## Architecture Overview

### Data Flow

```
User Action → View → AppViewModel → Store → Git/GitHub → File System
                                      ↓
                                 ConfigManager
```

### Key Components

| Component | File | Responsibility |
|-----------|------|----------------|
| **Models** | Models.swift | Task, Project, SyncMode data structures |
| **Store** | Store.swift | Git-backed persistence, GitHub sync |
| **AppViewModel** | AppViewModel.swift | Central state management, CRUD operations |
| **ConfigManager** | Config/ConfigManager.swift | User settings persistence (~/.lobs/config.json) |
| **GitHubService** | GitHubService.swift | GitHub Issues API client |
| **ContentView** | ContentView.swift | Root view, sidebar, navigation |

### State Management

**Centralized State:**
- `AppViewModel` is the single source of truth
- All views observe `@ObservedObject var vm: AppViewModel`
- State changes publish via `@Published` properties

**Persistence:**
- Task/project data → `lobs-control/state/`
- User settings → `~/.lobs/config.json`
- Never mix the two

**Git Sync:**
- All task changes commit to Git
- Optional auto-push (30s interval)
- Server polls Git for new work

---

## Common Pitfalls

### 1. Compilation Required

**Problem:** Implementing features without running Swift compiler.

**Why It Fails:**
- Syntax errors (unbalanced braces, typos)
- API mismatches (method doesn't exist)
- Type errors (wrong parameter types)

**Solution:**
```bash
# Always compile after changes
swift build

# Or build and run
./bin/build && ./bin/run
```

**If You Can't Compile:**
- Document assumptions clearly in implementation notes
- Mark code as "untested - requires compilation"
- Provide testing checklist for human review

---

### 2. AppViewModel API Assumptions

**Problem:** Calling methods or accessing properties that don't exist on AppViewModel.

**How to Verify:**
```bash
# Search for method/property definition
grep -n "func methodName" Sources/LobsDashboard/AppViewModel.swift
grep -n "@Published var propertyName" Sources/LobsDashboard/AppViewModel.swift
```

**Common Mistakes:**
- Assuming method exists without checking: `vm.someMethod()`
- Wrong parameter names or types
- Accessing private properties from views

**Solution:**
- Read `AppViewModel.swift` before making changes
- Check method signatures match your usage
- Use public API only (don't access private state)

---

### 3. State vs. UI Separation

**Problem:** Mixing AppViewModel state with SwiftUI @State.

**Wrong:**
```swift
// ❌ Don't put data model state in @State
@State private var currentTask: Task?
```

**Right:**
```swift
// ✅ UI state only in @State
@State private var showAddTaskSheet = false
@State private var searchText = ""

// ✅ Data model state in AppViewModel
@ObservedObject var vm: AppViewModel
// Access: vm.tasks, vm.selectedTaskId, etc.
```

**Rule:** If it persists or affects other views, it belongs in AppViewModel.

---

### 4. Git Operation Errors

**Problem:** Git commands fail silently or corrupt state.

**Common Causes:**
- Uncommitted changes conflict with pull
- Push fails due to outdated remote
- File not staged before commit

**Best Practices:**
```swift
// Always handle errors
do {
    try await vm.syncRepo()
} catch {
    // Show error to user
    print("Sync failed: \(error)")
}
```

**Testing Git Operations:**
```bash
# Check repo status before testing
cd ~/lobs-control
git status
git log --oneline -5

# Test app git operations
./bin/run

# Verify commits were created
git log --oneline -5
```

---

### 5. Settings Not Persisting

**Problem:** Changes to settings don't save or load correctly.

**Since Settings Migration (Feb 2026):**
- All settings → `~/.lobs/config.json`
- No more `UserDefaults`
- Changes must call `ConfigManager.shared.save(config)`

**How Settings Work:**
```swift
// Read setting
let autoSync = ConfigManager.shared.config.settings.autoSyncEnabled

// Write setting
var config = ConfigManager.shared.config
config.settings.autoSyncEnabled = true
try ConfigManager.shared.save(config)
```

**AppViewModel Pattern:**
```swift
// AppViewModel exposes settings helper
var settings: UserSettings {
    ConfigManager.shared.config.settings
}

// Save changes
func saveConfig() throws {
    try ConfigManager.shared.save(ConfigManager.shared.config)
}

// Usage in didSet
didSet {
    do {
        var config = ConfigManager.shared.config
        config.settings.propertyName = newValue
        try ConfigManager.shared.save(config)
    } catch {
        print("Failed to save: \(error)")
    }
}
```

**Check Settings File:**
```bash
cat ~/.lobs/config.json | jq .settings
```

---

### 6. Inbox UI Issues

**Problem:** Inbox view rendering errors or missing items.

**Common Issues:**
- Artifact path doesn't exist
- Document type not recognized
- Thread structure broken

**Debug Steps:**
1. Check artifact file exists:
   ```bash
   ls -la ~/lobs-control/artifacts/
   ```

2. Verify inbox item structure:
   ```bash
   cat ~/.lobs/config.json | jq .inbox
   ```

3. Test with minimal case:
   ```swift
   // Add debug print
   print("Inbox items count: \(vm.inboxItems.count)")
   vm.inboxItems.forEach { print("  - \($0.id): \($0.subject)") }
   ```

---

### 7. GitHub Sync Failures

**Problem:** Tasks not syncing with GitHub Issues.

**Common Causes:**
- Invalid access token (expired, wrong scope)
- Rate limit exceeded (5000/hour)
- Repository doesn't exist or no access
- Network connectivity

**Debug Checklist:**
```bash
# Test token manually
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user

# Check rate limit
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/rate_limit

# Verify repo access
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/repos/OWNER/REPO
```

**Enable Verbose Logging:**
```swift
// In GitHubService.swift, add debug prints
print("[GitHub] Creating issue: \(title)")
print("[GitHub] Response: \(response)")
```

---

## Development Workflow

### Making Changes

1. **Create a branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes:**
   - Edit Swift files
   - Follow existing code patterns
   - Add comments for complex logic

3. **Build and test:**
   ```bash
   swift build
   ./bin/run
   # Manually test your feature
   ```

4. **Run tests:**
   ```bash
   swift test
   ```

5. **Commit:**
   ```bash
   git add -A
   git commit -m "Add feature: your feature description"
   ```

6. **Push and open PR:**
   ```bash
   git push origin feature/your-feature-name
   # Open PR on GitHub
   ```

### Code Style

**Naming Conventions:**
- Types: `PascalCase` (Task, AppViewModel)
- Functions: `camelCase` (loadTasks, syncRepo)
- Properties: `camelCase` (selectedTaskId, isLoading)
- Constants: `camelCase` (maxRetries, defaultTimeout)

**SwiftUI Patterns:**
```swift
// ✅ Prefer computed properties over functions
var filteredTasks: [Task] {
    tasks.filter { $0.status == .active }
}

// ✅ Use @ViewBuilder for conditional views
@ViewBuilder
var detailView: some View {
    if let task = selectedTask {
        TaskDetailView(task: task)
    } else {
        Text("Select a task")
    }
}

// ✅ Extract complex views into separate components
var body: some View {
    VStack {
        HeaderView()  // Extracted
        ContentView() // Extracted
        FooterView()  // Extracted
    }
}
```

**Error Handling:**
```swift
// ✅ Always handle errors from async operations
do {
    try await vm.someOperation()
} catch {
    // Show user-friendly error
    alertMessage = "Operation failed: \(error.localizedDescription)"
    showAlert = true
}

// ✅ Use guard for early returns
guard let task = selectedTask else {
    print("No task selected")
    return
}
```

---

## Testing Strategy

### Unit Tests

**Location:** `Tests/LobsDashboardTests/`

**Running Tests:**
```bash
# All tests
swift test

# Specific test file
swift test --filter ToolbarButtonTests
```

**What to Test:**
- Data model logic (Task, Project transformations)
- Config serialization/deserialization
- Git operation wrappers
- Utility functions

**Example:**
```swift
import XCTest
@testable import LobsDashboard

final class ConfigTests: XCTestCase {
    func testSettingsPersistence() throws {
        let config = AppConfig(settings: UserSettings())
        // Test save/load logic
    }
}
```

### UI Tests

**Location:** `Tests/LobsDashboardTests/UI/`

**What to Test:**
- View rendering (snapshots if possible)
- User interactions (button clicks, text input)
- Navigation flows

### Manual Testing Checklist

Before submitting a PR, test these workflows:

**Task Management:**
- [ ] Create new task (⌘N)
- [ ] Edit task details
- [ ] Change task status
- [ ] Delete task
- [ ] Verify Git commit created

**Project Operations:**
- [ ] Create project (Kanban and Research)
- [ ] Switch between projects
- [ ] Rename project
- [ ] Delete project

**Sync Operations:**
- [ ] Manual sync (⌘R)
- [ ] Auto-sync (wait 30s)
- [ ] GitHub sync (if enabled)
- [ ] Verify no data loss

**Settings:**
- [ ] Change setting
- [ ] Quit and relaunch app
- [ ] Verify setting persisted

**Inbox:**
- [ ] View artifacts
- [ ] Mark as read
- [ ] Filter by status
- [ ] Delete inbox item

---

## Debugging Guide

### Build Errors

**"Cannot find type 'AppViewModel' in scope"**
- Missing import: Add `@testable import LobsDashboard`
- Wrong module: Check `Package.swift` target configuration

**"Type 'Task' has no member 'someProperty'"**
- Property doesn't exist: Check `Models.swift`
- Typo: Verify spelling matches exactly
- Wrong type: You might be using wrong model

**"Ambiguous reference to member 'init'"**
- Multiple init methods: Specify types explicitly
- Conflicting imports: Check for duplicate type names

### Runtime Errors

**"Failed to load config"**
```bash
# Check if config file exists
ls -la ~/.lobs/config.json

# Verify JSON structure
cat ~/.lobs/config.json | jq .

# Delete and regenerate if corrupt
rm ~/.lobs/config.json
./bin/run  # Will create new config with defaults
```

**"Git command failed"**
```bash
# Check repo status
cd ~/lobs-control
git status

# Reset to clean state (⚠️ loses uncommitted changes)
git reset --hard HEAD
git clean -fd

# Verify remote
git remote -v
```

**"Task not found"**
- Task ID mismatch: Check `state/tasks.json`
- File was deleted: Sync from remote
- State out of date: Pull latest changes

### Performance Issues

**Slow UI rendering:**
- Too many items in list: Add pagination
- Complex views: Use `.task()` for async loading
- Background loading: See `PERFORMANCE_FIXES.md`

**Git operations blocking UI:**
- Use async/await: `Task { await vm.syncRepo() }`
- Show loading indicator during operations
- Consider background queue for non-critical operations

### Logging

**Add Debug Logging:**
```swift
// Temporary debug logging
print("[DEBUG] \(#function): value=\(value)")

// Conditional logging
#if DEBUG
print("[DEBUG] Detailed debug info")
#endif
```

**View SwiftUI hierarchy:**
```swift
// Add to any view
.onAppear {
    print("View appeared: \(type(of: self))")
}
```

---

## Code Patterns

### Adding a New Setting

1. **Add to UserSettings.swift:**
```swift
struct UserSettings: Codable {
    var newSetting: Bool = false  // Add with default
}
```

2. **Add property to AppViewModel:**
```swift
@Published var newSetting: Bool = false {
    didSet {
        saveConfig()
    }
}
```

3. **Initialize in AppViewModel.init():**
```swift
self.newSetting = ConfigManager.shared.config.settings.newSetting
```

4. **Add to saveConfig():**
```swift
func saveConfig() {
    var config = ConfigManager.shared.config
    config.settings.newSetting = newSetting
    // ...
}
```

5. **Add UI in SettingsView:**
```swift
Toggle("New Setting", isOn: $vm.newSetting)
```

### Adding a New View

1. **Create view file:**
```swift
// Sources/LobsDashboard/MyNewView.swift
import SwiftUI

struct MyNewView: View {
    @ObservedObject var vm: AppViewModel
    
    var body: some View {
        Text("My new view")
    }
}

#Preview {
    MyNewView(vm: AppViewModel.preview)
}
```

2. **Add to ContentView navigation:**
```swift
NavigationLink(destination: MyNewView(vm: vm)) {
    Label("My View", systemImage: "star")
}
```

### Adding a Keyboard Shortcut

```swift
// In ContentView or relevant view
.keyboardShortcut("k", modifiers: [.command])
.keyboardShortcut("n", modifiers: [.command, .shift])
```

**Document shortcut:**
- Add to help text
- Add tooltip: `.help("Action (⌘K)")`
- Add to `COMMAND_PALETTE.md` or future shortcuts panel

---

## Pull Request Guidelines

### PR Title Format

```
[Component] Brief description

Examples:
[Inbox] Add bulk mark as read button
[Sync] Fix auto-push timing issue
[Settings] Add quiet hours configuration
[Docs] Update contributing guide
```

### PR Description Template

```markdown
## What Changed
Brief description of changes.

## Why
Explain motivation and context.

## How to Test
1. Step-by-step testing instructions
2. Expected behavior
3. Screenshots (if UI changes)

## Checklist
- [ ] Code compiles without errors
- [ ] Manual testing completed
- [ ] Unit tests added/updated (if applicable)
- [ ] Documentation updated (if needed)
- [ ] No regression (existing features work)
```

### Review Checklist

**Code Quality:**
- [ ] Follows Swift naming conventions
- [ ] No force unwraps (`!`) without justification
- [ ] Error handling for all async operations
- [ ] No debug prints left in code

**Architecture:**
- [ ] State management follows patterns
- [ ] No direct UserDefaults access (use ConfigManager)
- [ ] Git operations handle errors
- [ ] No blocking operations on main thread

**Testing:**
- [ ] Feature tested manually
- [ ] Edge cases considered
- [ ] No obvious performance issues

**Documentation:**
- [ ] Code comments for complex logic
- [ ] README updated if public API changed
- [ ] Implementation notes if needed

---

## Resources

### Documentation

- [README.md](README.md) — Project overview, setup, usage
- [ARCHITECTURE.md](docs/ux-improvement-plan.md) — Detailed architecture (see UX plan for current design)
- [COMMAND_PALETTE.md](COMMAND_PALETTE.md) — Command palette usage
- [SETTINGS_MIGRATION.md](SETTINGS_MIGRATION.md) — Settings architecture
- [PERFORMANCE_FIXES.md](PERFORMANCE_FIXES.md) — Performance patterns

### External Resources

- [Swift.org](https://swift.org/documentation/) — Swift language guide
- [SwiftUI](https://developer.apple.com/documentation/swiftui/) — SwiftUI documentation
- [Git](https://git-scm.com/doc) — Git documentation
- [GitHub API](https://docs.github.com/en/rest) — GitHub REST API

### Getting Help

- **Issues:** [GitHub Issues](https://github.com/RafeSymonds/lobs-dashboard/issues)
- **Questions:** Open a discussion or issue
- **Bugs:** Include reproduction steps, logs, and screenshots

---

## Appendix: Recent Failure Patterns

**Observed Issues (Feb 2026):**
- Multiple programmer agent task failures
- Common cause: Implementation without compilation testing
- Common cause: Assumptions about AppViewModel API

**Lessons Learned:**
1. Always compile after changes (or document inability to compile)
2. Verify method signatures before calling
3. Test edge cases (empty states, missing data)
4. Handle errors explicitly
5. Document assumptions clearly

**Prevention:**
- Use this guide's patterns
- Run `swift build` frequently
- Test manually before marking complete
- Ask for clarification when uncertain

---

**Built with ❤️ by the Lobs Dashboard team**

*Last updated: 2026-02-12*
