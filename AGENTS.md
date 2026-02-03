# lobs-dashboard — Agent Guide

macOS SwiftUI desktop app for managing tasks, projects, and research. Rafe's primary interface for interacting with Lobs.

## Quick Start
Open `Sources/LobsDashboard/` in Xcode or build via:
```bash
./scripts/generate-build-info.sh  # Embeds current commit hash for update detection
swift build
swift run
```

### Build Info
`BuildInfo.generated.swift` contains the git commit hash embedded at build time. This is used
to detect when the user has pulled new code but hasn't recompiled (shows "N to rebuild" indicator).
Run `scripts/generate-build-info.sh` before building, or add it as an Xcode Build Phase.

## Structure
```
Sources/LobsDashboard/
├── Models.swift          # Data models (Task, Project, ProjectType, ResearchTile, etc.)
├── Store.swift           # Git-backed persistence (reads/writes ~/lobs-control)
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

### Data Flow
```
Dashboard ←→ ~/lobs-control (git repo) ←→ Lobs workers
```
- Store.swift reads/writes JSON files in `~/lobs-control/state/`
- Git sync: pull → apply changes → commit → push
- On push failure: pull --rebase → re-apply from memory → retry push

### Views
- **OverviewView** — default landing page, shows stats across all projects
- **BoardView** — kanban columns for task projects
- **ResearchView** — tile grid + detail split for research projects
- **InboxView** — document reader for artifacts and inbox items

## Common Edits
- **Add a new view**: Create SwiftUI view, wire into ContentView or the appropriate project type view
- **Add a model field**: Update Models.swift (make new fields optional for backwards compat)
- **Change git sync behavior**: Edit Store.swift (asyncCommitAndMaybePush, optimisticUpdate)

## Testing
No formal test suite yet. Validate by building (`swift build`) and manual testing.

## Dependencies
- Pure SwiftUI + AppKit (NSViewRepresentable for spell checking)
- No external packages — everything is stdlib/system frameworks
