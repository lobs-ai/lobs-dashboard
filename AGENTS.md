# lobs-dashboard — Agent Guide

macOS SwiftUI desktop app for managing tasks, projects, and research. Rafe's primary interface for interacting with Lobs.

## Quick Start
Open `Sources/LobsDashboard/` in Xcode or build via:
```bash
./bin/build   # Generates build info, builds, saves hash to ~/.lobs/dashboard-build-commit
swift run
```

### Build Info
The build script (`bin/build`) saves the current HEAD commit hash to
`~/.lobs/dashboard-build-commit` after each successful build. The running app reads this file
at runtime to detect when you've pulled new code but haven't recompiled (shows "N to rebuild"
indicator). `BuildInfo.generated.swift` serves as a compile-time fallback if the hash file
doesn't exist.

## Structure
```
Sources/LobsDashboard/
├── Models.swift          # Data models (Task, Project, SyncMode, GitHubConfig, etc.)
├── Store.swift           # Git-backed persistence + GitHub sync logic
├── GitHubService.swift   # GitHub API client (Issues CRUD, rate limiting, errors)
├── AppViewModel.swift    # Main view model (state, CRUD, git sync)
├── ContentView.swift     # Root view (sidebar, project picker, create sheets)
├── BoardView.swift       # Kanban board (columns: active, waiting, blocked, done)
├── OverviewView.swift    # Dashboard home screen (stats, project cards, activity feed)
├── ResearchView.swift    # Research project view (tile grid, detail panel, requests)
├── InboxView.swift       # Inbox for design docs and artifacts
└── SpellCheckingTextEditor.swift  # NSTextView wrapper with spell check
```

## Key Concepts

### Project Types
- **Kanban** — traditional board with task columns (active, waiting, blocked, done)
- **Research** — tile-based workspace with notes, links, findings, comparisons + "Ask Lobs" requests

### Sync Modes: Personal vs. Collaborative

The dashboard supports two sync modes per project:

#### Local Mode (Personal)
- Tasks stored as JSON files in `~/lobs-control/state/tasks/`
- Single-user workflow
- Git-backed for versioning and sync with Lobs workers
- Default mode for all projects

#### GitHub Mode (Collaborative)
- Tasks synced bidirectionally with GitHub Issues
- Enables team collaboration on task management
- Local JSON files serve as cache
- GitHub is source of truth for collaborative projects

**Configuration** (in `Models.swift`):
```swift
struct Project {
  var syncMode: SyncMode = .local  // or .github
  var githubConfig: GitHubConfig?
}

struct GitHubConfig {
  var owner: String        // GitHub org/user
  var repo: String         // Repository name
  var accessToken: String? // Personal access token
  var syncLabels: [String]? // Optional labels to add to all issues
}
```

**Label Schema** (GitHub → Local mapping):
- `status:active` → TaskStatus.active
- `status:waiting` → TaskStatus.waiting
- `status:blocked` → TaskStatus.blocked
- `status:done` → TaskStatus.done
- `work:not_started` → WorkState.notStarted
- `work:in_progress` → WorkState.inProgress
- `work:failed` → WorkState.failed
- `work:completed` → WorkState.completed

**GitHub Token Setup**:
1. Generate a GitHub Personal Access Token with `repo` scope
2. Store in `githubConfig.accessToken` for the project
3. Token is used for all API calls (create/update/list issues)

**Sync Behavior**:
- **On task creation**: Creates local JSON + GitHub issue (if GitHub mode)
- **On task load**: Merges local tasks with GitHub issues (matching by `githubIssueNumber`)
- **Conflict resolution**: Local version takes precedence
- **New GitHub issues**: Added to local cache automatically
- **Updates**: Currently local-only (future: bidirectional sync on task updates)

### Data Flow
```
Dashboard ←→ ~/lobs-control (git repo) ←→ Lobs workers
         ↕
    GitHub Issues (collaborative mode)
```
- Store.swift reads/writes JSON files in `~/lobs-control/state/`
- GitHubService.swift handles GitHub API calls
- Git sync: pull → apply changes → commit → push
- On push failure: pull --rebase → re-apply from memory → retry push
- GitHub sync: create/update issues with label-based status tracking

### Views
- **OverviewView** — default landing page, shows stats across all projects
- **BoardView** — kanban columns for task projects
- **ResearchView** — tile grid + detail split for research projects
- **InboxView** — document reader for artifacts and inbox items

## Common Edits
- **Add a new view**: Create SwiftUI view, wire into ContentView or the appropriate project type view
- **Add a model field**: Update Models.swift (make new fields optional for backwards compat)
- **Change git sync behavior**: Edit Store.swift (asyncCommitAndMaybePush, optimisticUpdate)
- **Add GitHub sync for task updates**: Modify `optimisticUpdate` in AppViewModel to call `saveTaskToGitHub` when project uses GitHub mode
- **Extend label schema**: Update `parseTaskStatus`, `parseWorkState` in Store.swift + add new labels in `saveTaskToGitHub`

## Testing
No formal test suite yet. Validate by building (`swift build`) and manual testing.

## Dependencies
- Pure SwiftUI + AppKit (NSViewRepresentable for spell checking)
- No external packages — everything is stdlib/system frameworks
